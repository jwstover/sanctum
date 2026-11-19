defmodule Sanctum.Homebrew.SetMetadataTest do
  @moduledoc """
  Set metadata editing through `HomebrewSet :update` — chiefly the open kind
  combobox's `:kind` argument (`Changes.ResolveSetKind`). Plain users, so
  policies apply.
  """

  use Sanctum.DataCase, async: true

  import Sanctum.AccountsFixtures

  alias Sanctum.Homebrew
  alias Sanctum.Homebrew.SetKind

  setup do
    creator = user_fixture()
    project = Homebrew.create_project!(%{name: "Hazard Pack", attestation: true}, actor: creator)

    set =
      Homebrew.create_set!(%{homebrew_project_id: project.id, name: "Kingpin"}, actor: creator)

    %{creator: creator, project: project, set: set}
  end

  defp kind_count, do: SetKind |> Ash.read!(authorize?: false) |> length()

  defp set_kind(set, text, actor) do
    Homebrew.update_set(set, %{kind: text}, actor: actor, load: [:set_kind])
  end

  describe "list_project_set_kinds" do
    test "returns official kinds and this project's custom kinds only", ctx do
      {:ok, _} = set_kind(ctx.set, "Hazard Deck", ctx.creator)

      other_user = user_fixture()
      other = Homebrew.create_project!(%{name: "Other", attestation: true}, actor: other_user)

      Homebrew.create_set_kind!(
        %{homebrew_project_id: other.id, key: "theirs", label: "Theirs"},
        actor: other_user
      )

      labels =
        ctx.project.id
        |> Homebrew.list_project_set_kinds!(actor: ctx.creator)
        |> Enum.map(& &1.label)

      assert "Hero" in labels
      assert "Hazard Deck" in labels
      refute "Theirs" in labels
    end
  end

  describe "the :kind argument" do
    test "blank text leaves the set unclassified", ctx do
      {:ok, set} = set_kind(ctx.set, "Hero", ctx.creator)
      assert set.set_kind.key == "hero"

      {:ok, set} = set_kind(set, "  ", ctx.creator)
      assert is_nil(set.set_kind_id)

      {:ok, set} = set_kind(set, nil, ctx.creator)
      assert is_nil(set.set_kind_id)
    end

    test "omitting it leaves the kind alone", ctx do
      {:ok, set} = set_kind(ctx.set, "Hero", ctx.creator)
      {:ok, set} = Homebrew.update_set(set, %{name: "Renamed"}, actor: ctx.creator)
      assert set.set_kind_id
    end

    test "an official label (any case) selects the official kind without a new row", ctx do
      before = kind_count()

      assert {:ok, %{set_kind: %{origin: :official, key: "hero"}}} =
               set_kind(ctx.set, " hero ", ctx.creator)

      assert {:ok, %{set_kind: %{origin: :official, key: "player_cards"}}} =
               set_kind(ctx.set, "Player Cards", ctx.creator)

      assert kind_count() == before
    end

    test "novel text mints a project-scoped custom kind, reused next time", ctx do
      before = kind_count()

      assert {:ok, %{set_kind: kind}} = set_kind(ctx.set, "Hazard Deck", ctx.creator)
      assert kind.origin == :custom
      assert kind.homebrew_project_id == ctx.project.id
      assert kind.label == "Hazard Deck"
      assert kind.key == "hazard_deck"
      assert kind_count() == before + 1

      assert {:ok, %{set_kind: again}} = set_kind(ctx.set, "hazard deck", ctx.creator)
      assert again.id == kind.id
      assert kind_count() == before + 1
    end

    test "no kind string is rejected", ctx do
      for text <- ["!!!", "Ωmega", "_leading", "Café Run", String.duplicate("x", 200)] do
        assert {:ok, %{set_kind: %SetKind{origin: :custom} = kind}} =
                 set_kind(ctx.set, text, ctx.creator)

        assert kind.label == String.trim(text)
      end
    end

    test "another project's identically labelled kind is not reused", ctx do
      other_user = user_fixture()
      other = Homebrew.create_project!(%{name: "Other", attestation: true}, actor: other_user)

      other_set =
        Homebrew.create_set!(%{homebrew_project_id: other.id, name: "Theirs"}, actor: other_user)

      {:ok, %{set_kind: theirs}} = set_kind(other_set, "Hazard Deck", other_user)
      {:ok, %{set_kind: mine}} = set_kind(ctx.set, "Hazard Deck", ctx.creator)

      assert mine.id != theirs.id
      assert mine.homebrew_project_id == ctx.project.id
    end

    test "a failed update rolls back a freshly minted kind", ctx do
      before = kind_count()

      assert {:error, _} =
               Homebrew.update_set(ctx.set, %{name: "", kind: "Brand New Kind"},
                 actor: ctx.creator
               )

      assert kind_count() == before
    end

    test "a non-owner is forbidden before any kind is minted", ctx do
      before = kind_count()

      assert {:error, %Ash.Error.Forbidden{}} = set_kind(ctx.set, "Sneaky Kind", user_fixture())
      assert kind_count() == before
    end
  end

  describe "other metadata" do
    test "saves name, description, banner and tags", ctx do
      assert {:ok, set} =
               Homebrew.update_set(
                 ctx.set,
                 %{
                   name: "Kingpin Rising",
                   description: "# Big\n\nTrouble",
                   banner_url: "https://img.test/banner.png",
                   tags: ["street", "noir"]
                 },
                 actor: ctx.creator
               )

      assert set.name == "Kingpin Rising"
      assert set.description == "# Big\n\nTrouble"
      assert set.banner_url == "https://img.test/banner.png"
      assert set.tags == ["street", "noir"]
    end

    test "banner URLs must be https", ctx do
      for url <- ["http://img.test/b.png", "javascript:alert(1)", "img.png"] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Homebrew.update_set(ctx.set, %{banner_url: url}, actor: ctx.creator)
      end

      assert {:ok, %{banner_url: nil}} =
               Homebrew.update_set(ctx.set, %{banner_url: nil}, actor: ctx.creator)
    end
  end
end
