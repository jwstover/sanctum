defmodule Sanctum.Decks.UniquenessTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  alias Sanctum.Decks.Deck
  alias Sanctum.Decks.Uniqueness
  alias Sanctum.Games.Card
  alias Sanctum.Games.CardSide

  # Build a valid hero (a card with hero + alter-ego sides, plus the Hero record)
  # so the deck's ValidateHero passes.
  defp valid_hero(name, set) do
    hero_card = create(Card, attrs: %{set: set, is_multi_sided: true})

    create(CardSide,
      attrs: %{
        card_id: hero_card.id,
        name: name,
        type: :hero,
        code: "#{hero_card.code}a",
        side_identifier: "A",
        is_primary_side: true
      }
    )

    create(CardSide,
      attrs: %{
        card_id: hero_card.id,
        name: "AE #{name}",
        type: :alter_ego,
        code: "#{hero_card.code}b",
        side_identifier: "B",
        is_primary_side: false
      }
    )

    {:ok, hero} =
      Sanctum.Heroes.find_or_create_hero(%{
        hero_name: name,
        alter_ego_name: "AE #{name}",
        set: set,
        base_code: hero_card.base_code,
        card_id: hero_card.id
      })

    hero
  end

  # A card with a primary side of the given ownership. `:hero` cards should be
  # excluded from the calculation; anything else is a "choice" card.
  defp card_with_ownership(ownership) do
    card = create(Card)

    create(CardSide,
      attrs: %{
        card_id: card.id,
        code: "#{card.code}a",
        side_identifier: "A",
        is_primary_side: true,
        type: :ally,
        ownership: ownership
      }
    )

    card.id
  end

  defp make_deck(hero, title, card_ids) do
    slots = Enum.map(card_ids, &%{card_id: &1, quantity: 1})

    Deck
    |> Ash.Changeset.for_create(:create_with_cards, %{
      title: title,
      hero_id: hero.id,
      slots: slots
    })
    |> Ash.create!(authorize?: false)
  end

  defp reload(deck) do
    Ash.get!(Deck, deck.id, authorize?: false)
  end

  describe "recompute_all/1" do
    test "clones tie at the bottom, a divergent deck tops out, and hero cards are ignored" do
      hero = valid_hero("Spider-Man", "spider_man")

      # Two shared signature cards every deck runs — must not create similarity.
      [h1, h2] = [card_with_ownership(:hero), card_with_ownership(:hero)]

      choice = for _ <- 1..8, do: card_with_ownership(:basic)
      [c1, c2, c3, c4, c5, c6, c7, c8] = choice

      a = make_deck(hero, "A", [h1, h2, c1, c2, c3, c4])
      b = make_deck(hero, "B (clone of A)", [h1, h2, c1, c2, c3, c4])
      c = make_deck(hero, "C (divergent)", [h1, h2, c5, c6, c7, c8])

      {:ok, summary} = Uniqueness.recompute_all(min_hero_decks: 2)
      assert summary.ranked == 3

      a = reload(a)
      b = reload(b)
      c = reload(c)

      # A and B are exact clones of each other's *choices* → identical, minimal.
      assert a.uniqueness_score == b.uniqueness_score
      assert a.uniqueness_score == 0.0

      # C shares only the two hero cards with A/B. Because hero cards are
      # excluded, C shares nothing that counts → maximally unique, no neighbor.
      assert c.uniqueness_score == 1.0
      assert is_nil(c.nearest_deck_id)

      # Percentiles rank C above the clones.
      assert a.uniqueness_percentile == 0
      assert b.uniqueness_percentile == 0
      assert c.uniqueness_percentile == 100

      # Nearest neighbor points clones at each other.
      assert a.nearest_deck_id == b.id
      assert b.nearest_deck_id == a.id
    end

    test "heroes below the min-deck threshold get a score but no percentile" do
      hero = valid_hero("Thor", "thor")
      c1 = card_with_ownership(:basic)
      c2 = card_with_ownership(:basic)

      d1 = make_deck(hero, "One", [c1, c2])
      d2 = make_deck(hero, "Two", [c1])

      {:ok, summary} = Uniqueness.recompute_all(min_hero_decks: 10)
      assert summary.ranked == 0

      d1 = reload(d1)
      d2 = reload(d2)

      # Scores are still computed (they share c1)...
      assert is_float(d1.uniqueness_score)
      assert is_float(d2.uniqueness_score)
      # ...but the group is too small to rank.
      assert is_nil(d1.uniqueness_percentile)
      assert is_nil(d2.uniqueness_percentile)
    end
  end
end
