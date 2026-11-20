defmodule Sanctum.Homebrew.DirectoryTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  import Ecto.Query
  import Sanctum.AccountsFixtures
  import Sanctum.HomebrewFixtures

  alias Sanctum.Games
  alias Sanctum.Homebrew

  setup do
    murdock = user_fixture(%{username: "matt_murdock"})
    nelson = user_fixture(%{username: "foggy"})

    murdock_project =
      Homebrew.create_project!(%{name: "Hell's Kitchen", attestation: true}, actor: murdock)

    nelson_project = Homebrew.create_project!(%{name: "Nelson", attestation: true}, actor: nelson)

    %{
      murdock: murdock,
      nelson: nelson,
      murdock_project: murdock_project,
      nelson_project: nelson_project
    }
  end

  defp set!(project, actor, name, attrs \\ %{}) do
    set = Homebrew.create_set!(%{homebrew_project_id: project.id, name: name}, actor: actor)

    case attrs do
      empty when map_size(empty) == 0 -> set
      attrs -> Homebrew.update_set!(set, attrs, actor: actor)
    end
  end

  defp published!(project, actor, name, attrs \\ %{}) do
    project |> set!(actor, name, attrs) |> publish_set!(actor)
  end

  defp names(input \\ %{}, opts \\ []) do
    input
    |> Homebrew.list_directory_sets!(opts)
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  defp backdate!(set, days) do
    at = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

    {1, _} =
      Sanctum.Repo.update_all(
        from(s in "homebrew_sets", where: s.id == type(^set.id, :binary_id)),
        set: [attested_at: at]
      )
  end

  describe "visibility" do
    test "only published sets are listed — never private or unlisted", ctx do
      published!(ctx.murdock_project, ctx.murdock, "Daredevil")
      set!(ctx.murdock_project, ctx.murdock, "Secret")

      ctx.murdock_project
      |> set!(ctx.murdock, "Elektra")
      |> then(&Homebrew.set_set_visibility!(&1, :unlisted, actor: ctx.murdock))

      admin = admin_user_fixture()

      for actor <- [nil, ctx.murdock, ctx.nelson, admin] do
        assert names(%{}, actor: actor) == ["Daredevil"]
      end
    end

    test "a set that goes back to private leaves the directory", ctx do
      set = published!(ctx.murdock_project, ctx.murdock, "Daredevil")
      Homebrew.set_set_visibility!(set, :private, actor: ctx.murdock)
      assert names() == []
    end
  end

  describe "facets" do
    setup ctx do
      published!(ctx.murdock_project, ctx.murdock, "Daredevil", %{kind: "Hero", tags: ["noir"]})

      published!(ctx.murdock_project, ctx.murdock, "Kingpin", %{
        kind: "Scenario",
        tags: ["noir", "crime"]
      })

      published!(ctx.nelson_project, ctx.nelson, "Loose Scans")
      published!(ctx.nelson_project, ctx.nelson, "Hazards", %{kind: "Hazard Deck"})
      published!(ctx.nelson_project, ctx.nelson, "Leftovers", %{kind: "Other"})

      old = published!(ctx.nelson_project, ctx.nelson, "Old Hero", %{kind: "Hero"})
      backdate!(old, 90)
      :ok
    end

    test "kind", _ctx do
      assert names(%{kind: "hero"}) == ["Daredevil", "Old Hero"]
      assert names(%{kind: "scenario"}) == ["Kingpin"]
      assert names(%{kind: "modular"}) == []
    end

    test "no kind, the official other kind and custom kinds all land under Other", _ctx do
      assert names(%{kind: "other"}) == ["Hazards", "Leftovers", "Loose Scans"]
    end

    test "creator", _ctx do
      assert names(%{creator: "matt_murdock"}) == ["Daredevil", "Kingpin"]
      assert names(%{creator: "MATT_MURDOCK"}) == ["Daredevil", "Kingpin"]
      assert names(%{creator: "nobody"}) == []
    end

    test "tag", _ctx do
      assert names(%{tag: "noir"}) == ["Daredevil", "Kingpin"]
      assert names(%{tag: "crime"}) == ["Kingpin"]
      assert names(%{tag: "nope"}) == []
    end

    test "recency", _ctx do
      assert "Old Hero" not in names(%{recency: "month"})
      assert "Old Hero" in names(%{recency: "year"})
      assert length(names(%{recency: "week"})) == 5
    end

    test "facets combine", _ctx do
      assert names(%{kind: "hero", creator: "matt_murdock"}) == ["Daredevil"]
      assert names(%{kind: "hero", recency: "month"}) == ["Daredevil"]
      assert names(%{tag: "noir", kind: "scenario", creator: "matt_murdock"}) == ["Kingpin"]
      assert names(%{tag: "noir", creator: "foggy"}) == []
    end

    test "newest first", _ctx do
      assert List.last(Enum.map(Homebrew.list_directory_sets!(), & &1.name)) == "Old Hero"
    end

    test "facet options come from published sets only", ctx do
      ctx.murdock_project
      |> set!(ctx.murdock, "Secret", %{tags: ["hidden"]})

      admin = admin_user_fixture(%{username: "stick"})

      for actor <- [nil, admin] do
        facets = Homebrew.directory_facets!(actor: actor)
        assert facets.creators == ["foggy", "matt_murdock"]
        assert facets.tags == ["crime", "noir"]
      end
    end
  end

  test "card_count counts the set's cards", ctx do
    set = published!(ctx.murdock_project, ctx.murdock, "Daredevil")

    for n <- 1..3 do
      Games.create_custom_card!(
        %{homebrew_set_id: set.id, card_sides: [%{image_url: "https://img.test/#{n}.png"}]},
        actor: ctx.murdock
      )
    end

    assert [%{card_count: 3}] = Homebrew.list_directory_sets!()
  end

  test "published descendants exclude the set itself and non-published children", ctx do
    root = published!(ctx.murdock_project, ctx.murdock, "Daredevil")

    child =
      ctx.murdock_project
      |> set!(ctx.murdock, "Nemesis")
      |> then(&Homebrew.set_set_parent!(&1, root.id, actor: ctx.murdock))
      |> publish_set!(ctx.murdock)

    hidden =
      ctx.murdock_project
      |> set!(ctx.murdock, "Draft")
      |> then(&Homebrew.set_set_parent!(&1, root.id, actor: ctx.murdock))

    ctx.murdock_project
    |> set!(ctx.murdock, "Deep")
    |> then(&Homebrew.set_set_parent!(&1, hidden.id, actor: ctx.murdock))
    |> publish_set!(ctx.murdock)

    for actor <- [nil, ctx.murdock, admin_user_fixture()] do
      descendants = Homebrew.list_published_descendants!(root.id, actor: actor)
      assert descendants |> Enum.map(& &1.name) |> Enum.sort() == ["Deep", "Nemesis"]
      assert child.id in Enum.map(descendants, & &1.id)
    end
  end
end
