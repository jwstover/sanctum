defmodule Sanctum.Homebrew.SetMetadataTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  import Sanctum.AccountsFixtures

  alias Sanctum.Homebrew
  alias Sanctum.Homebrew.SetKind

  require Ash.Query

  setup do
    creator = user_fixture()
    project = Homebrew.create_project!(%{name: "Hazard Pack", attestation: true}, actor: creator)

    set =
      Homebrew.create_set!(%{homebrew_project_id: project.id, name: "Kingpin"}, actor: creator)

    %{creator: creator, project: project, set: set}
  end

  defp kind_count, do: SetKind |> Ash.read!(authorize?: false) |> length()

  defp params(overrides) do
    Map.merge(
      %{"name" => "Kingpin", "description" => "", "banner_url" => "", "tags" => "", "kind" => ""},
      overrides
    )
  end

  describe "resolve_set_kind/3" do
    test "blank text is unclassified", ctx do
      assert {:ok, nil} = Homebrew.resolve_set_kind(ctx.project.id, "  ", ctx.creator)
      assert {:ok, nil} = Homebrew.resolve_set_kind(ctx.project.id, nil, ctx.creator)
    end

    test "an official label (any case) selects the official kind without a new row", ctx do
      before = kind_count()

      assert {:ok, %{origin: :official, key: "hero"}} =
               Homebrew.resolve_set_kind(ctx.project.id, " hero ", ctx.creator)

      assert {:ok, %{origin: :official, key: "player_cards"}} =
               Homebrew.resolve_set_kind(ctx.project.id, "Player Cards", ctx.creator)

      assert kind_count() == before
    end

    test "novel text mints a project-scoped custom kind, reused next time", ctx do
      before = kind_count()

      assert {:ok, kind} = Homebrew.resolve_set_kind(ctx.project.id, "Hazard Deck", ctx.creator)
      assert kind.origin == :custom
      assert kind.homebrew_project_id == ctx.project.id
      assert kind.label == "Hazard Deck"
      assert kind.key == "hazard_deck"
      assert kind_count() == before + 1

      assert {:ok, again} = Homebrew.resolve_set_kind(ctx.project.id, "hazard deck", ctx.creator)
      assert again.id == kind.id
      assert kind_count() == before + 1
    end

    test "no kind string is rejected", ctx do
      for text <- ["!!!", "Ωmega", "_leading", "Café Run", String.duplicate("x", 200)] do
        assert {:ok, %SetKind{origin: :custom} = kind} =
                 Homebrew.resolve_set_kind(ctx.project.id, text, ctx.creator)

        assert kind.label == String.trim(text)
      end
    end

    test "another project's identically labelled kind is not reused", ctx do
      other_user = user_fixture()
      other = Homebrew.create_project!(%{name: "Other", attestation: true}, actor: other_user)
      {:ok, theirs} = Homebrew.resolve_set_kind(other.id, "Hazard Deck", other_user)

      assert {:ok, mine} = Homebrew.resolve_set_kind(ctx.project.id, "Hazard Deck", ctx.creator)
      assert mine.id != theirs.id
      assert mine.homebrew_project_id == ctx.project.id
    end
  end

  describe "update_set_metadata/3" do
    test "saves name, description, banner, tags and a novel kind", ctx do
      assert {:ok, set} =
               Homebrew.update_set_metadata(
                 ctx.set,
                 params(%{
                   "name" => "Kingpin Rising",
                   "description" => "# Big\n\nTrouble",
                   "banner_url" => "https://img.test/banner.png",
                   "tags" => "street, Noir , street,,",
                   "kind" => "Villain Pack"
                 }),
                 ctx.creator
               )

      assert set.name == "Kingpin Rising"
      assert set.description == "# Big\n\nTrouble"
      assert set.banner_url == "https://img.test/banner.png"
      assert set.tags == ["street", "Noir"]
      assert set.set_kind.label == "Villain Pack"
      assert set.set_kind.homebrew_project_id == ctx.project.id
    end

    test "a kind can be set and then cleared back to unclassified", ctx do
      {:ok, set} = Homebrew.update_set_metadata(ctx.set, params(%{"kind" => "Hero"}), ctx.creator)
      assert set.set_kind.key == "hero"

      {:ok, set} = Homebrew.update_set_metadata(set, params(%{"kind" => ""}), ctx.creator)
      assert is_nil(set.set_kind_id)
      assert is_nil(set.set_kind)
    end

    test "a failed update rolls back a freshly minted kind", ctx do
      before = kind_count()

      assert {:error, _} =
               Homebrew.update_set_metadata(
                 ctx.set,
                 params(%{"name" => "", "kind" => "Brand New Kind"}),
                 ctx.creator
               )

      assert kind_count() == before
    end

    test "another user cannot edit the set", ctx do
      assert {:error, _} =
               Homebrew.update_set_metadata(ctx.set, params(%{"name" => "Mine"}), user_fixture())
    end
  end
end
