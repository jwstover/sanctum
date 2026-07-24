defmodule Sanctum.Homebrew.CustomCardTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  import Sanctum.AccountsFixtures

  alias Sanctum.Games.Card
  alias Sanctum.Homebrew

  require Ash.Query

  setup do
    creator = user_fixture()

    project =
      Homebrew.create_project!(%{name: "My Pack", attestation: true}, actor: creator)

    %{creator: creator, other: user_fixture(), project: project}
  end

  defp create_card!(project, actor, sides) do
    {:ok, card} =
      Homebrew.create_custom_card(
        %{homebrew_project_id: project.id, card_sides: sides},
        actor
      )

    Ash.load!(card, :card_sides, authorize?: false)
  end

  describe "create_custom" do
    test "mints origin, codes, and side conventions", ctx do
      card =
        create_card!(ctx.project, ctx.creator, [
          %{image_url: "https://img.test/a.png", filename: "spider_swing-kick.png"}
        ])

      assert card.origin == :custom
      assert card.homebrew_project_id == ctx.project.id
      assert "custom-" <> _uuid = card.base_code
      assert card.code == card.base_code
      refute card.is_multi_sided

      assert [side] = card.card_sides
      assert side.code == card.code <> "a"
      assert side.side_identifier == "a"
      assert side.is_primary_side
      assert side.name == "Spider Swing Kick"
      assert side.image_url == "https://img.test/a.png"
    end

    test "two sides make a multi-sided card", ctx do
      card =
        create_card!(ctx.project, ctx.creator, [
          %{image_url: "https://img.test/front.png", name: "Hero Face"},
          %{image_url: "https://img.test/back.png", name: "Alter-Ego Face"}
        ])

      assert card.is_multi_sided

      assert [%{side_identifier: "a", is_primary_side: true}, %{side_identifier: "b"}] =
               Enum.sort_by(card.card_sides, & &1.side_identifier)
    end

    test "name falls back to Untitled without a filename", ctx do
      card = create_card!(ctx.project, ctx.creator, [%{image_url: "https://img.test/x.png"}])

      assert [%{name: "Untitled"}] = card.card_sides
    end

    test "a side without an image is rejected", ctx do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Homebrew.create_custom_card(
                 %{homebrew_project_id: ctx.project.id, card_sides: [%{name: "No Image"}]},
                 ctx.creator
               )

      assert Exception.message(error) =~ "missing an image"
    end

    test "cannot create into another user's project", ctx do
      assert {:error, %Ash.Error.Forbidden{}} =
               Homebrew.create_custom_card(
                 %{
                   homebrew_project_id: ctx.project.id,
                   card_sides: [%{image_url: "https://img.test/a.png"}]
                 },
                 ctx.other
               )
    end

    test "cannot smuggle origin/code/set through create_custom", ctx do
      for forbidden <- [%{origin: :official}, %{code: "01001"}, %{set: "core"}] do
        attrs =
          Map.merge(
            %{
              homebrew_project_id: ctx.project.id,
              card_sides: [%{image_url: "https://img.test/a.png"}]
            },
            forbidden
          )

        assert {:error, _} = Homebrew.create_custom_card(attrs, ctx.creator)
      end
    end
  end

  describe "update_custom / destroy_custom" do
    setup ctx do
      %{card: create_card!(ctx.project, ctx.creator, [%{image_url: "https://img.test/a.png"}])}
    end

    test "creator can update card-level flags", ctx do
      assert {:ok, updated} =
               ctx.card
               |> Ash.Changeset.for_update(:update_custom, %{deck_limit: 1, unique: true},
                 actor: ctx.creator
               )
               |> Ash.update()

      assert updated.deck_limit == 1
      assert updated.unique
    end

    test "another user cannot update or destroy the card", ctx do
      assert {:error, _} =
               ctx.card
               |> Ash.Changeset.for_update(:update_custom, %{deck_limit: 1}, actor: ctx.other)
               |> Ash.update()

      assert {:error, _} = Homebrew.destroy_custom_card(ctx.card.id, ctx.other)
    end

    test "creator can destroy; sides cascade", ctx do
      [side] = ctx.card.card_sides

      assert :ok = Homebrew.destroy_custom_card(ctx.card.id, ctx.creator)
      assert {:error, _} = Ash.get(Card, ctx.card.id, authorize?: false)
      assert {:error, _} = Ash.get(Sanctum.Games.CardSide, side.id, authorize?: false)
    end

    test "custom actions cannot touch official cards", ctx do
      official = create(Card)

      assert {:error, _} =
               official
               |> Ash.Changeset.for_update(:update_custom, %{deck_limit: 1}, actor: ctx.creator)
               |> Ash.update()
    end
  end

  describe "enrichment (update_custom card_sides)" do
    setup ctx do
      %{card: create_card!(ctx.project, ctx.creator, [%{image_url: "https://img.test/a.png"}])}
    end

    test "creator enriches side metadata and card flags in one call", ctx do
      [side] = ctx.card.card_sides

      {:ok, updated} =
        Homebrew.enrich_custom_card(
          ctx.card,
          %{
            deck_limit: 1,
            unique: true,
            card_sides: [
              %{
                id: side.id,
                name: "Web Kick",
                type: :event,
                aspect: "justice",
                cost: 2,
                attack: 3,
                traits: ["Aerial", "Attack"],
                text: "Deal 5 damage."
              }
            ]
          },
          ctx.creator
        )

      assert updated.deck_limit == 1
      assert updated.unique

      side = Ash.get!(Sanctum.Games.CardSide, side.id, authorize?: false)
      assert side.name == "Web Kick"
      assert side.type == :event
      assert side.aspect == "justice"
      assert side.cost == 2
      assert %Sanctum.Games.Stat{value: 3} = side.attack
      assert side.traits == ["Aerial", "Attack"]
      assert side.text == "Deal 5 damage."
      # Minted fields untouched
      assert side.code == ctx.card.code <> "a"
      assert side.is_primary_side
    end

    test "omitting a side never destroys it", ctx do
      two_sided =
        create_card!(ctx.project, ctx.creator, [
          %{image_url: "https://img.test/f.png", name: "Front"},
          %{image_url: "https://img.test/b.png", name: "Back"}
        ])

      [side_a, side_b] = Enum.sort_by(two_sided.card_sides, & &1.side_identifier)

      {:ok, _} =
        Homebrew.enrich_custom_card(
          two_sided,
          %{card_sides: [%{id: side_a.id, name: "Front Enriched"}]},
          ctx.creator
        )

      assert {:ok, _} = Ash.get(Sanctum.Games.CardSide, side_b.id, authorize?: false)
    end

    # manage_relationship filters side maps to :enrich's accept list, so
    # non-enrichable keys are silently dropped — never applied.
    test "minted/image fields cannot be smuggled through enrichment", ctx do
      [side] = ctx.card.card_sides

      for forbidden <- [
            %{code: "01001a"},
            %{side_identifier: "b"},
            %{is_primary_side: false},
            %{image_url: "https://evil.test/x.png"}
          ] do
        {:ok, _} =
          Homebrew.enrich_custom_card(
            ctx.card,
            %{card_sides: [Map.put(forbidden, :id, side.id)]},
            ctx.creator
          )
      end

      unchanged = Ash.get!(Sanctum.Games.CardSide, side.id, authorize?: false)
      assert unchanged.code == side.code
      assert unchanged.side_identifier == "a"
      assert unchanged.is_primary_side
      assert unchanged.image_url == side.image_url
    end

    test "a foreign side id is rejected", ctx do
      other_card =
        create_card!(ctx.project, ctx.creator, [%{image_url: "https://img.test/o.png"}])

      [foreign_side] = other_card.card_sides

      assert {:error, _} =
               Homebrew.enrich_custom_card(
                 ctx.card,
                 %{card_sides: [%{id: foreign_side.id, name: "Hijack"}]},
                 ctx.creator
               )
    end

    test "another user cannot enrich; direct :enrich on a side is forbidden", ctx do
      [side] = ctx.card.card_sides

      assert {:error, _} =
               Homebrew.enrich_custom_card(
                 ctx.card.id,
                 %{card_sides: [%{id: side.id, name: "Hijack"}]},
                 ctx.other
               )

      assert {:error, %Ash.Error.Forbidden{}} =
               side
               |> Ash.Changeset.for_update(:enrich, %{name: "Hijack"}, actor: ctx.creator)
               |> Ash.update()
    end

    test "full stat axes round-trip through map params", ctx do
      [side] = ctx.card.card_sides

      {:ok, _} =
        Homebrew.enrich_custom_card(
          ctx.card,
          %{
            card_sides: [
              %{
                id: side.id,
                attack: %{"value" => "2", "star" => "true", "consequential" => "1"},
                health: %{value: 12, scaling: :per_player}
              }
            ]
          },
          ctx.creator
        )

      side = Ash.get!(Sanctum.Games.CardSide, side.id, authorize?: false)

      assert %Sanctum.Games.Stat{value: 2, star: true, consequential: 1, scaling: :flat} =
               side.attack

      assert %Sanctum.Games.Stat{value: 12, scaling: :per_player} = side.health

      # An all-blank stat map (an untouched form row) collapses back to absent.
      {:ok, _} =
        Homebrew.enrich_custom_card(
          ctx.card,
          %{
            card_sides: [
              %{id: side.id, attack: %{"value" => "", "star" => "false", "consequential" => ""}}
            ]
          },
          ctx.creator
        )

      assert is_nil(Ash.get!(Sanctum.Games.CardSide, side.id, authorize?: false).attack)
    end

    test "blank optional inputs stay blank", ctx do
      [side] = ctx.card.card_sides

      {:ok, _} =
        Homebrew.enrich_custom_card(
          ctx.card,
          %{card_sides: [%{id: side.id, cost: "", attack: "", aspect: nil}]},
          ctx.creator
        )

      side = Ash.get!(Sanctum.Games.CardSide, side.id, authorize?: false)
      assert is_nil(side.cost)
      assert is_nil(side.attack)
      assert is_nil(side.aspect)
    end
  end

  describe "pair_custom" do
    setup ctx do
      front = create_card!(ctx.project, ctx.creator, [%{image_url: "https://img.test/f.png"}])
      back = create_card!(ctx.project, ctx.creator, [%{image_url: "https://img.test/b.png"}])
      %{front: front, back: back}
    end

    test "merges the donor as side b and destroys its card row", ctx do
      [donor_side] = ctx.back.card_sides

      {:ok, paired} = Homebrew.pair_custom_cards(ctx.front.id, ctx.back.id, ctx.creator)

      assert paired.is_multi_sided

      sides =
        paired
        |> Ash.load!(:card_sides, authorize?: false)
        |> Map.fetch!(:card_sides)
        |> Enum.sort_by(& &1.side_identifier)

      assert [%{side_identifier: "a", is_primary_side: true}, side_b] = sides
      assert side_b.side_identifier == "b"
      refute side_b.is_primary_side
      assert side_b.code == ctx.front.code <> "b"
      assert side_b.card_id == ctx.front.id
      # The donor's side ROW survived, re-parented (same id, image intact).
      assert side_b.id == donor_side.id
      assert side_b.image_url == "https://img.test/b.png"

      assert {:error, _} = Ash.get(Sanctum.Games.Card, ctx.back.id, authorize?: false)
    end

    test "donor from another user's project is not found", ctx do
      other_project =
        Homebrew.create_project!(%{name: "Other's", attestation: true}, actor: ctx.other)

      donor = create_card!(other_project, ctx.other, [%{image_url: "https://img.test/x.png"}])

      assert {:error, _} = Homebrew.pair_custom_cards(ctx.front.id, donor.id, ctx.creator)
    end

    test "donor from the actor's other project is rejected", ctx do
      second_project =
        Homebrew.create_project!(%{name: "Second", attestation: true}, actor: ctx.creator)

      donor = create_card!(second_project, ctx.creator, [%{image_url: "https://img.test/x.png"}])

      assert {:error, error} = Homebrew.pair_custom_cards(ctx.front.id, donor.id, ctx.creator)
      assert Exception.message(error) =~ "same project"
    end

    test "multi-sided cards and self-pairs are rejected", ctx do
      {:ok, paired} = Homebrew.pair_custom_cards(ctx.front.id, ctx.back.id, ctx.creator)

      extra = create_card!(ctx.project, ctx.creator, [%{image_url: "https://img.test/e.png"}])

      # Multi-sided target
      assert {:error, _} = Homebrew.pair_custom_cards(paired.id, extra.id, ctx.creator)
      # Multi-sided donor
      assert {:error, _} = Homebrew.pair_custom_cards(extra.id, paired.id, ctx.creator)
      # Self
      assert {:error, _} = Homebrew.pair_custom_cards(extra.id, extra.id, ctx.creator)
    end

    test "another user cannot pair the creator's cards", ctx do
      assert {:error, _} = Homebrew.pair_custom_cards(ctx.front.id, ctx.back.id, ctx.other)
    end
  end

  describe "unpair_custom" do
    setup ctx do
      front = create_card!(ctx.project, ctx.creator, [%{image_url: "https://img.test/f.png"}])
      back = create_card!(ctx.project, ctx.creator, [%{image_url: "https://img.test/b.png"}])
      {:ok, paired} = Homebrew.pair_custom_cards(front.id, back.id, ctx.creator)
      %{paired: paired}
    end

    test "splits side b into a fresh single-sided card", ctx do
      {:ok, {updated, new_card}} = Homebrew.unpair_custom_card(ctx.paired.id, ctx.creator)

      refute updated.is_multi_sided
      refute new_card.is_multi_sided
      assert new_card.origin == :custom
      assert new_card.homebrew_project_id == ctx.paired.homebrew_project_id
      assert "custom-" <> _ = new_card.code
      assert new_card.base_code == new_card.code
      assert new_card.deck_limit == ctx.paired.deck_limit

      [moved] =
        new_card |> Ash.load!(:card_sides, authorize?: false) |> Map.fetch!(:card_sides)

      assert moved.side_identifier == "a"
      assert moved.is_primary_side
      assert moved.code == new_card.code <> "a"
      assert moved.image_url == "https://img.test/b.png"

      [remaining] =
        updated |> Ash.load!(:card_sides, authorize?: false) |> Map.fetch!(:card_sides)

      assert remaining.side_identifier == "a"
      assert remaining.image_url == "https://img.test/f.png"
    end

    test "single-sided cards cannot be unpaired; other users get not-found", ctx do
      single = create_card!(ctx.project, ctx.creator, [%{image_url: "https://img.test/s.png"}])

      assert {:error, _} = Homebrew.unpair_custom_card(single.id, ctx.creator)
      assert {:error, _} = Homebrew.unpair_custom_card(ctx.paired.id, ctx.other)
    end

    test "privacy is unaffected after pair/unpair", ctx do
      {:ok, {updated, new_card}} = Homebrew.unpair_custom_card(ctx.paired.id, ctx.creator)

      assert {:error, _} = Ash.get(Sanctum.Games.Card, updated.id, actor: ctx.other)
      assert {:error, _} = Ash.get(Sanctum.Games.Card, new_card.id, actor: ctx.other)
    end
  end

  describe "official catalog boundaries" do
    test "non-admins cannot use the official mutations", ctx do
      assert {:error, %Ash.Error.Forbidden{}} =
               Card
               |> Ash.Changeset.for_create(:create, %{code: "88888", base_code: "88888"},
                 actor: ctx.creator
               )
               |> Ash.create()
    end

    test "sync-style numeric upserts cannot collide with custom rows", ctx do
      card = create_card!(ctx.project, ctx.creator, [%{image_url: "https://img.test/a.png"}])

      synced = create(Card, attrs: %{code: "77777", base_code: "77777"})

      assert synced.id != card.id
      assert Ash.get!(Card, card.id, authorize?: false).origin == :custom
    end
  end
end
