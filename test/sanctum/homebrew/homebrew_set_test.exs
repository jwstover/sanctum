defmodule Sanctum.Homebrew.HomebrewSetTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  import Sanctum.AccountsFixtures

  alias Sanctum.Homebrew
  alias Sanctum.Homebrew.{HomebrewSet, SetKind}

  require Ash.Query

  setup do
    creator = user_fixture()
    other = user_fixture()

    %{
      creator: creator,
      other: other,
      project: project_fixture(creator, "Daredevil"),
      other_project: project_fixture(other, "Kingpin")
    }
  end

  defp project_fixture(actor, name),
    do: Homebrew.create_project!(%{name: name, attestation: true}, actor: actor)

  defp set_fixture(project, actor, attrs \\ %{}) do
    Homebrew.create_set!(
      Map.merge(%{name: "Daredevil Hero Pack", homebrew_project_id: project.id}, attrs),
      actor: actor
    )
  end

  defp publish!(set, actor), do: Homebrew.set_set_visibility!(set, :published, actor: actor)

  defp reload!(set), do: Ash.get!(HomebrewSet, set.id, authorize?: false)
  defp ids(sets), do: sets |> Enum.map(& &1.id) |> Enum.sort()

  defp official_kind!(key) do
    SetKind
    |> Ash.Query.filter(key == ^key and is_nil(homebrew_project_id))
    |> Ash.read_one!(authorize?: false)
  end

  defp custom_kind!(project, actor, key \\ "hazard_deck") do
    Homebrew.create_set_kind!(
      %{key: key, label: "Hazard Deck", homebrew_project_id: project.id},
      actor: actor
    )
  end

  describe "create" do
    test "derives creator from the project and applies defaults", ctx do
      set = set_fixture(ctx.project, ctx.creator)

      assert set.creator_id == ctx.creator.id
      assert set.homebrew_project_id == ctx.project.id
      assert set.visibility == :private
      assert set.maturity == :draft
      assert set.attestation == false
      assert set.tags == []
      assert is_nil(set.slug)
      assert is_nil(set.set_kind_id)
      assert is_nil(set.parent_set_id)
    end

    test "accepts the editable fields", ctx do
      hero = official_kind!("hero")

      set =
        set_fixture(ctx.project, ctx.creator, %{
          description: "Street-level justice",
          banner_url: "https://example.com/banner.png",
          tags: ["street-level"],
          maturity: :beta,
          attestation: true,
          set_kind_id: hero.id
        })

      assert set.description == "Street-level justice"
      assert set.banner_url == "https://example.com/banner.png"
      assert set.tags == ["street-level"]
      assert set.maturity == :beta
      assert set.attestation == true
      assert set.set_kind_id == hero.id

      loaded = Homebrew.get_set!(set.id, actor: ctx.creator, load: [:set_kind])
      assert loaded.set_kind.key == "hero"
    end

    test "creator_id is never user input", ctx do
      assert {:error, %Ash.Error.Invalid{} = err} =
               Homebrew.create_set(
                 %{name: "X", homebrew_project_id: ctx.project.id, creator_id: ctx.other.id},
                 actor: ctx.creator
               )

      assert Enum.any?(err.errors, &match?(%Ash.Error.Invalid.NoSuchInput{}, &1))

      # Even a tampered changeset is overridden by the before_action stamp.
      set =
        HomebrewSet
        |> Ash.Changeset.for_create(:create, %{name: "X", homebrew_project_id: ctx.project.id},
          actor: ctx.creator
        )
        |> Ash.Changeset.force_change_attribute(:creator_id, ctx.other.id)
        |> Ash.create!()

      assert reload!(set).creator_id == ctx.creator.id
      refute reload!(set).creator_id == ctx.other.id
    end

    test "an admin creating in someone else's project stamps the project's creator", ctx do
      admin = admin_user_fixture()

      set = set_fixture(ctx.project, admin)

      assert set.creator_id == ctx.creator.id
      refute set.creator_id == admin.id
    end

    test "creating a set in a project the actor does not own is forbidden", ctx do
      assert {:error, %Ash.Error.Forbidden{}} =
               Homebrew.create_set(%{name: "X", homebrew_project_id: ctx.project.id},
                 actor: ctx.other
               )

      assert {:error, %Ash.Error.Forbidden{}} =
               Homebrew.create_set(%{name: "X", homebrew_project_id: ctx.project.id}, actor: nil)

      assert Ash.count!(HomebrewSet, authorize?: false) == 0
    end

    test "an unauthorized create is forbidden regardless of parent/kind ids (no membership oracle)",
         ctx do
      # The same-project validations run only after the policy passes, so the
      # error class must not differ between "parent is in that project" and
      # "parent is not" for an actor who does not own the project.
      inside = set_fixture(ctx.project, ctx.creator, %{name: "Inside"})
      elsewhere = set_fixture(ctx.other_project, ctx.other, %{name: "Elsewhere"})

      their_kind = custom_kind!(ctx.project, ctx.creator)

      for attrs <- [
            %{parent_set_id: inside.id},
            %{parent_set_id: elsewhere.id},
            %{parent_set_id: Ash.UUIDv7.generate()},
            %{set_kind_id: their_kind.id},
            %{set_kind_id: Ash.UUIDv7.generate()}
          ] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 Homebrew.create_set(
                   Map.merge(%{name: "X", homebrew_project_id: ctx.project.id}, attrs),
                   actor: ctx.other
                 )
      end

      assert Ash.count!(HomebrewSet, authorize?: false) == 2
    end

    test "requires a project", ctx do
      assert {:error, _} = Homebrew.create_set(%{name: "Orphan"}, actor: ctx.creator)
      assert Ash.count!(HomebrewSet, authorize?: false) == 0
    end
  end

  describe "read visibility" do
    setup ctx do
      %{set: set_fixture(ctx.project, ctx.creator)}
    end

    test "another user's private set reads as not-found, not forbidden", ctx do
      result = Homebrew.get_set(ctx.set.id, actor: ctx.other)

      assert {:error, %Ash.Error.Invalid{}} = result
      refute match?({:error, %Ash.Error.Forbidden{}}, result)

      assert {:error, %Ash.Error.Invalid{}} = Homebrew.get_set(ctx.set.id)
      assert {:ok, %HomebrewSet{}} = Homebrew.get_set(ctx.set.id, actor: ctx.creator)
    end

    test "unlisted sets stay creator-only for now", ctx do
      Homebrew.set_set_visibility!(ctx.set, :unlisted, actor: ctx.creator)

      assert {:error, %Ash.Error.Invalid{}} = Homebrew.get_set(ctx.set.id, actor: ctx.other)
      assert {:error, %Ash.Error.Invalid{}} = Homebrew.get_set(ctx.set.id, actor: nil)
      assert {:ok, %HomebrewSet{}} = Homebrew.get_set(ctx.set.id, actor: ctx.creator)
    end

    test "published sets are visible to everyone", ctx do
      publish!(ctx.set, ctx.creator)

      assert {:ok, %HomebrewSet{}} = Homebrew.get_set(ctx.set.id, actor: ctx.other)
      assert {:ok, %HomebrewSet{}} = Homebrew.get_set(ctx.set.id, actor: nil)
    end

    test "anonymous reads still see published sets alongside private ones (no nil-actor collapse)",
         ctx do
      published =
        ctx.project |> set_fixture(ctx.creator, %{name: "Pub"}) |> publish!(ctx.creator)

      private = set_fixture(ctx.project, ctx.creator, %{name: "Priv"})
      theirs = set_fixture(ctx.other_project, ctx.other, %{name: "Theirs"})

      pub_id = published.id

      assert {:ok, %HomebrewSet{id: ^pub_id}} = Homebrew.get_set(published.id)

      # ctx.set is private too — exactly one row survives the anonymous read.
      # Folding the two read checks into one `or` expr makes this return [].
      assert ids(Ash.read!(HomebrewSet, actor: nil)) == [pub_id]
      assert ids(Homebrew.list_project_sets!(ctx.project.id, actor: nil)) == [pub_id]

      assert ids(Ash.read!(HomebrewSet, actor: ctx.other)) == Enum.sort([pub_id, theirs.id])

      assert ids(Ash.read!(HomebrewSet, actor: ctx.creator)) ==
               Enum.sort([ctx.set.id, pub_id, private.id])
    end

    test "admins see everything", ctx do
      assert {:ok, %HomebrewSet{}} = Homebrew.get_set(ctx.set.id, actor: admin_user_fixture())
    end

    test "for_creator lists only the actor's sets", ctx do
      mine_published =
        ctx.project |> set_fixture(ctx.creator, %{name: "Pub"}) |> publish!(ctx.creator)

      theirs_published =
        ctx.other_project |> set_fixture(ctx.other, %{name: "Theirs"}) |> publish!(ctx.other)

      mine = Homebrew.list_my_sets!(actor: ctx.creator)
      assert ids(mine) == Enum.sort([ctx.set.id, mine_published.id])
      refute theirs_published.id in ids(mine)

      assert ids(Homebrew.list_my_sets!(actor: ctx.other)) == [theirs_published.id]
    end

    test "by_project lists a project's sets, scoped by visibility", ctx do
      published =
        ctx.project |> set_fixture(ctx.creator, %{name: "Pub"}) |> publish!(ctx.creator)

      _theirs_private = set_fixture(ctx.other_project, ctx.other, %{name: "Theirs"})

      assert ids(Homebrew.list_project_sets!(ctx.project.id, actor: ctx.creator)) ==
               Enum.sort([ctx.set.id, published.id])

      assert ids(Homebrew.list_project_sets!(ctx.project.id, actor: ctx.other)) == [published.id]

      assert Homebrew.list_project_sets!(ctx.other_project.id, actor: ctx.creator) == []
    end
  end

  describe "update / set_visibility / destroy" do
    setup ctx do
      %{set: set_fixture(ctx.project, ctx.creator)}
    end

    test "creator can update; others cannot even see it", ctx do
      assert {:ok, %HomebrewSet{name: "Renamed", tags: ["x"], attestation: true}} =
               Homebrew.update_set(
                 ctx.set,
                 %{name: "Renamed", tags: ["x"], attestation: true},
                 actor: ctx.creator
               )

      assert {:error, _} = Homebrew.update_set(ctx.set, %{name: "Hijacked"}, actor: ctx.other)
      assert {:error, _} = Homebrew.update_set(ctx.set, %{name: "Hijacked"}, actor: nil)

      assert reload!(ctx.set).name == "Renamed"
    end

    test "visibility is only editable through set_visibility", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.update_set(ctx.set, %{visibility: :published}, actor: ctx.creator)

      assert reload!(ctx.set).visibility == :private
    end

    test "project and creator are not editable", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.update_set(
                 ctx.set,
                 %{homebrew_project_id: ctx.other_project.id},
                 actor: ctx.creator
               )

      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.update_set(ctx.set, %{creator_id: ctx.other.id}, actor: ctx.creator)

      reloaded = reload!(ctx.set)
      assert reloaded.homebrew_project_id == ctx.project.id
      assert reloaded.creator_id == ctx.creator.id
    end

    test "set_visibility walks the ladder for the creator only", ctx do
      assert %HomebrewSet{visibility: :published} = publish!(ctx.set, ctx.creator)

      assert {:error, _} = Homebrew.set_set_visibility(ctx.set, :private, actor: ctx.other)
      assert {:error, _} = Homebrew.set_set_visibility(ctx.set, :private, actor: nil)

      assert reload!(ctx.set).visibility == :published
    end

    test "visibility enum rejects unknown values", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.set_set_visibility(ctx.set, :secret, actor: ctx.creator)

      assert reload!(ctx.set).visibility == :private
    end

    test "creator can destroy; others cannot", ctx do
      assert {:error, _} = Homebrew.destroy_set(ctx.set, actor: ctx.other)
      assert %HomebrewSet{} = reload!(ctx.set)

      assert :ok = Homebrew.destroy_set(ctx.set, actor: ctx.creator)
      assert {:error, _} = Ash.get(HomebrewSet, ctx.set.id, authorize?: false)
    end
  end

  describe "parent sets" do
    test "a child attaches to a parent in the same project", ctx do
      parent = set_fixture(ctx.project, ctx.creator)

      child =
        set_fixture(ctx.project, ctx.creator, %{name: "Nemesis", parent_set_id: parent.id})

      assert child.parent_set_id == parent.id

      loaded = Homebrew.get_set!(parent.id, actor: ctx.creator, load: [:child_sets])
      assert ids(loaded.child_sets) == [child.id]
    end

    test "a parent in another project is rejected", ctx do
      set = set_fixture(ctx.project, ctx.creator)
      theirs = set_fixture(ctx.other_project, ctx.other)

      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.create_set(
                 %{name: "X", homebrew_project_id: ctx.project.id, parent_set_id: theirs.id},
                 actor: ctx.creator
               )

      # The creator's *own* other project is still another project.
      mine_elsewhere = set_fixture(project_fixture(ctx.creator, "Second"), ctx.creator)

      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.create_set(
                 %{
                   name: "X",
                   homebrew_project_id: ctx.project.id,
                   parent_set_id: mine_elsewhere.id
                 },
                 actor: ctx.creator
               )

      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.update_set(set, %{parent_set_id: theirs.id}, actor: ctx.creator)

      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.update_set(set, %{parent_set_id: Ash.UUIDv7.generate()},
                 actor: ctx.creator
               )

      assert is_nil(reload!(set).parent_set_id)
    end

    test "a set cannot be its own parent", ctx do
      set = set_fixture(ctx.project, ctx.creator)

      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.update_set(set, %{parent_set_id: set.id}, actor: ctx.creator)

      assert is_nil(reload!(set).parent_set_id)
    end

    test "destroying the parent cascades to its children", ctx do
      parent = set_fixture(ctx.project, ctx.creator)

      child =
        set_fixture(ctx.project, ctx.creator, %{name: "Nemesis", parent_set_id: parent.id})

      assert :ok = Homebrew.destroy_set(parent, actor: ctx.creator)
      assert {:error, _} = Ash.get(HomebrewSet, child.id, authorize?: false)
    end

    test "destroying the project cascades its sets", ctx do
      a = set_fixture(ctx.project, ctx.creator, %{name: "A"})
      b = set_fixture(ctx.project, ctx.creator, %{name: "B"})

      assert :ok = Homebrew.destroy_project(ctx.project, actor: ctx.creator)

      assert {:error, _} = Ash.get(HomebrewSet, a.id, authorize?: false)
      assert {:error, _} = Ash.get(HomebrewSet, b.id, authorize?: false)
    end
  end

  describe "set kind" do
    test "accepts official kinds and the project's own custom kinds", ctx do
      hero = official_kind!("hero")
      mine = custom_kind!(ctx.project, ctx.creator)

      set = set_fixture(ctx.project, ctx.creator, %{set_kind_id: mine.id})
      assert set.set_kind_id == mine.id

      assert {:ok, %HomebrewSet{set_kind_id: hero_id}} =
               Homebrew.update_set(set, %{set_kind_id: hero.id}, actor: ctx.creator)

      assert hero_id == hero.id

      assert {:ok, %HomebrewSet{set_kind_id: nil}} =
               Homebrew.update_set(set, %{set_kind_id: nil}, actor: ctx.creator)
    end

    test "rejects a custom kind from another project", ctx do
      theirs = custom_kind!(ctx.other_project, ctx.other)

      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.create_set(
                 %{name: "X", homebrew_project_id: ctx.project.id, set_kind_id: theirs.id},
                 actor: ctx.creator
               )

      # The creator's *own* other project is still another project.
      mine_elsewhere = custom_kind!(project_fixture(ctx.creator, "Second"), ctx.creator)

      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.create_set(
                 %{
                   name: "X",
                   homebrew_project_id: ctx.project.id,
                   set_kind_id: mine_elsewhere.id
                 },
                 actor: ctx.creator
               )

      assert Ash.count!(HomebrewSet, authorize?: false) == 0

      set = set_fixture(ctx.project, ctx.creator)

      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.update_set(set, %{set_kind_id: theirs.id}, actor: ctx.creator)

      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.update_set(set, %{set_kind_id: Ash.UUIDv7.generate()}, actor: ctx.creator)

      assert is_nil(reload!(set).set_kind_id)
    end

    test "destroying the kind nilifies set_kind_id", ctx do
      kind = custom_kind!(ctx.project, ctx.creator)

      set = set_fixture(ctx.project, ctx.creator, %{set_kind_id: kind.id})
      assert set.set_kind_id == kind.id

      assert :ok = Homebrew.destroy_set_kind(kind, actor: ctx.creator)
      assert is_nil(reload!(set).set_kind_id)
    end
  end
end
