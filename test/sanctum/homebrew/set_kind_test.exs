defmodule Sanctum.Homebrew.SetKindTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  import Sanctum.AccountsFixtures

  alias Sanctum.Homebrew
  alias Sanctum.Homebrew.SetKind

  require Ash.Query

  setup do
    creator = user_fixture()

    project =
      Homebrew.create_project!(%{name: "Hazard Pack", attestation: true}, actor: creator)

    %{creator: creator, other: user_fixture(), project: project}
  end

  defp project_fixture(actor, name \\ "Another Pack") do
    Homebrew.create_project!(%{name: name, attestation: true}, actor: actor)
  end

  defp custom_kind!(project, actor, attrs \\ %{}) do
    Homebrew.create_set_kind!(
      Map.merge(
        %{key: "hazard_deck", label: "Hazard Deck", homebrew_project_id: project.id},
        attrs
      ),
      actor: actor
    )
  end

  defp keys(kinds), do: Enum.map(kinds, & &1.key)

  describe "official kinds" do
    test "are seeded and readable by an anonymous actor, in sort order" do
      kinds = Homebrew.list_set_kinds!(actor: nil)

      official = Enum.filter(kinds, &(&1.origin == :official))

      assert keys(official) == SetKind.official_keys()

      assert keys(official) == [
               "hero",
               "scenario",
               "modular",
               "aspect",
               "player_cards",
               "alt_art",
               "campaign",
               "other"
             ]

      assert Enum.all?(official, &is_nil(&1.homebrew_project_id))
      assert Enum.map(official, & &1.sort_order) == Enum.sort(Enum.map(official, & &1.sort_order))
    end

    test "seeding again is a no-op" do
      before = SetKind |> Ash.Query.filter(origin == :official) |> Ash.count!(authorize?: false)

      Sanctum.Release.seed_set_kinds()

      assert SetKind |> Ash.Query.filter(origin == :official) |> Ash.count!(authorize?: false) ==
               before
    end

    test "a non-admin cannot mint an official kind", ctx do
      assert {:error, %Ash.Error.Forbidden{}} =
               SetKind
               |> Ash.Changeset.for_create(:create, %{key: "sneaky", label: "Sneaky"},
                 actor: ctx.creator
               )
               |> Ash.create()

      assert {:error, %Ash.Error.Forbidden{}} =
               SetKind
               |> Ash.Changeset.for_create(:create, %{key: "sneaky", label: "Sneaky"}, actor: nil)
               |> Ash.create()
    end

    test "an admin can mint an official kind" do
      admin = admin_user_fixture()

      {:ok, kind} =
        SetKind
        |> Ash.Changeset.for_create(:create, %{key: "nemesis", label: "Nemesis"}, actor: admin)
        |> Ash.create()

      assert kind.origin == :official
      assert is_nil(kind.homebrew_project_id)
    end

    test "a non-admin cannot update or destroy an official kind", ctx do
      hero =
        SetKind
        |> Ash.Query.filter(key == "hero" and is_nil(homebrew_project_id))
        |> Ash.read_one!(authorize?: false)

      assert {:error, _} = Homebrew.update_set_kind(hero, %{label: "Villain"}, actor: ctx.creator)
      assert {:error, _} = Homebrew.destroy_set_kind(hero, actor: ctx.creator)

      assert %SetKind{label: "Hero"} = Ash.get!(SetKind, hero.id, authorize?: false)
    end

    test "an admin can update an official kind" do
      admin = admin_user_fixture()

      other =
        SetKind
        |> Ash.Query.filter(key == "other" and is_nil(homebrew_project_id))
        |> Ash.read_one!(authorize?: false)

      {:ok, updated} = Homebrew.update_set_kind(other, %{sort_order: 200}, actor: admin)
      assert updated.sort_order == 200
    end
  end

  describe "create_set_kind (custom, project-scoped)" do
    test "the creator mints a kind pinned to :custom and the project", ctx do
      kind = custom_kind!(ctx.project, ctx.creator)

      assert kind.origin == :custom
      assert kind.key == "hazard_deck"
      assert kind.label == "Hazard Deck"
      assert kind.sort_order == 100
      assert kind.homebrew_project_id == ctx.project.id
    end

    test "origin cannot be overridden through create_custom", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.create_set_kind(
                 %{
                   key: "hazard_deck",
                   label: "Hazard Deck",
                   origin: :official,
                   homebrew_project_id: ctx.project.id
                 },
                 actor: ctx.creator
               )
    end

    test "requires a project", ctx do
      assert {:error, _} =
               Homebrew.create_set_kind(%{key: "orphan", label: "Orphan"}, actor: ctx.creator)
    end

    test "another user cannot mint a kind in someone else's project", ctx do
      assert {:error, %Ash.Error.Forbidden{}} =
               Homebrew.create_set_kind(
                 %{key: "hijack", label: "Hijack", homebrew_project_id: ctx.project.id},
                 actor: ctx.other
               )
    end

    test "a nil actor is forbidden", ctx do
      assert {:error, %Ash.Error.Forbidden{}} =
               Homebrew.create_set_kind(
                 %{key: "ghost", label: "Ghost", homebrew_project_id: ctx.project.id},
                 actor: nil
               )
    end

    test "key format is enforced structurally, never against a list", ctx do
      for bad <- ["Hazard Deck", "-leading", "UPPER", "", "with.dot"] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Homebrew.create_set_kind(
                   %{key: bad, label: "Bad", homebrew_project_id: ctx.project.id},
                   actor: ctx.creator
                 )
      end

      # Any well-formed key is fine — including one that is not an official kind
      # and one that shadows an official kind inside the project.
      for good <- ["hazard-deck", "x9", "hero"] do
        assert {:ok, %SetKind{key: ^good}} =
                 Homebrew.create_set_kind(
                   %{key: good, label: "Good", homebrew_project_id: ctx.project.id},
                   actor: ctx.creator
                 )
      end
    end
  end

  describe "key uniqueness" do
    test "two different projects can each define the same key", ctx do
      mine = custom_kind!(ctx.project, ctx.creator)

      theirs_project = project_fixture(ctx.other)
      theirs = custom_kind!(theirs_project, ctx.other)

      second_project = project_fixture(ctx.creator, "Second Pack")
      second = custom_kind!(second_project, ctx.creator)

      assert mine.key == theirs.key
      assert theirs.key == second.key
      assert length(Enum.uniq([mine.id, theirs.id, second.id])) == 3
    end

    test "the same key twice in one project is rejected", ctx do
      custom_kind!(ctx.project, ctx.creator)

      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.create_set_kind(
                 %{key: "hazard_deck", label: "Dup", homebrew_project_id: ctx.project.id},
                 actor: ctx.creator
               )
    end

    test "official keys are globally unique (NULL project is not distinct)" do
      admin = admin_user_fixture()

      assert {:error, %Ash.Error.Invalid{}} =
               SetKind
               |> Ash.Changeset.for_create(:create, %{key: "hero", label: "Hero Again"},
                 actor: admin
               )
               |> Ash.create()
    end
  end

  describe "read visibility" do
    test "a private custom kind is visible only to its creator", ctx do
      kind = custom_kind!(ctx.project, ctx.creator)

      assert kind.id in Enum.map(Homebrew.list_set_kinds!(actor: ctx.creator), & &1.id)
      refute kind.id in Enum.map(Homebrew.list_set_kinds!(actor: ctx.other), & &1.id)
      refute kind.id in Enum.map(Homebrew.list_set_kinds!(actor: nil), & &1.id)
      assert kind.id in Enum.map(Homebrew.list_set_kinds!(actor: admin_user_fixture()), & &1.id)
    end

    test "official kinds stay visible alongside a private custom kind", ctx do
      custom_kind!(ctx.project, ctx.creator)

      for actor <- [ctx.creator, ctx.other, nil] do
        listed = Homebrew.list_set_kinds!(actor: actor)
        assert Enum.all?(SetKind.official_keys(), &(&1 in keys(listed)))
      end
    end

    test "publishing the project makes its kinds visible to everyone", ctx do
      kind = custom_kind!(ctx.project, ctx.creator)
      Homebrew.set_project_visibility!(ctx.project, :published, actor: ctx.creator)

      for actor <- [ctx.other, nil] do
        assert kind.id in Enum.map(Homebrew.list_set_kinds!(actor: actor), & &1.id)
      end
    end

    test "unlisted projects keep their kinds creator-only", ctx do
      kind = custom_kind!(ctx.project, ctx.creator)
      Homebrew.set_project_visibility!(ctx.project, :unlisted, actor: ctx.creator)

      refute kind.id in Enum.map(Homebrew.list_set_kinds!(actor: ctx.other), & &1.id)
    end

    test "default ordering is sort_order then label", ctx do
      custom_kind!(ctx.project, ctx.creator, %{key: "zeta", label: "Zeta", sort_order: 0})
      custom_kind!(ctx.project, ctx.creator, %{key: "beta", label: "Beta", sort_order: 100})
      custom_kind!(ctx.project, ctx.creator, %{key: "alpha", label: "Alpha", sort_order: 100})

      listed = Homebrew.list_set_kinds!(actor: ctx.creator)

      assert hd(listed).key == "zeta"

      hundreds = Enum.filter(listed, &(&1.sort_order == 100))
      assert Enum.map(hundreds, & &1.label) == Enum.sort(Enum.map(hundreds, & &1.label))
      assert ["Alpha", "Beta", "Other"] == Enum.map(hundreds, & &1.label)
    end
  end

  describe "update / destroy" do
    test "the creator can update and destroy their own custom kind", ctx do
      kind = custom_kind!(ctx.project, ctx.creator)

      {:ok, updated} =
        Homebrew.update_set_kind(kind, %{label: "Hazards", sort_order: 7}, actor: ctx.creator)

      assert updated.label == "Hazards"
      assert updated.sort_order == 7

      assert :ok = Homebrew.destroy_set_kind(updated, actor: ctx.creator)
      assert {:error, _} = Ash.get(SetKind, kind.id, authorize?: false)
    end

    test "another user cannot update or destroy it", ctx do
      kind = custom_kind!(ctx.project, ctx.creator)

      assert {:error, _} = Homebrew.update_set_kind(kind, %{label: "Hijacked"}, actor: ctx.other)
      assert {:error, _} = Homebrew.destroy_set_kind(kind, actor: ctx.other)
      assert {:error, _} = Homebrew.update_set_kind(kind, %{label: "Hijacked"}, actor: nil)

      assert %SetKind{label: "Hazard Deck"} = Ash.get!(SetKind, kind.id, authorize?: false)
    end

    test "key is not editable", ctx do
      kind = custom_kind!(ctx.project, ctx.creator)

      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.update_set_kind(kind, %{key: "renamed"}, actor: ctx.creator)
    end
  end

  test "destroying the project cascades its custom kinds", ctx do
    kind = custom_kind!(ctx.project, ctx.creator)

    :ok = Homebrew.destroy_project(ctx.project, actor: ctx.creator)

    assert {:error, _} = Ash.get(SetKind, kind.id, authorize?: false)
  end
end
