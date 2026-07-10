defmodule Sanctum.Decks.DeckTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  alias Sanctum.Decks.Deck

  describe "create" do
    test "creates a deck with a hero" do
      hero_card = create(Sanctum.Games.Card, attrs: %{base_code: "01001", set: "spider_man"})
      # Create hero CardSide
      _side =
        create(Sanctum.Games.CardSide,
          attrs: %{
            card_id: hero_card.id,
            name: "Spider-Man",
            type: :hero,
            code: hero_card.code,
            side_identifier: "A",
            is_primary_side: true
          }
        )

      alter_ego_card = create(Sanctum.Games.Card, attrs: %{base_code: "01001", set: "spider_man"})
      # Create alter ego CardSide
      _side =
        create(Sanctum.Games.CardSide,
          attrs: %{
            card_id: alter_ego_card.id,
            name: "Peter Parker",
            type: :alter_ego,
            code: alter_ego_card.code,
            side_identifier: "B",
            is_primary_side: true
          }
        )

      # Create Hero record
      {:ok, hero} =
        Sanctum.Heroes.find_or_create_hero(%{
          hero_name: "Spider-Man",
          alter_ego_name: "Peter Parker",
          set: "spider_man",
          base_code: hero_card.base_code,
          card_id: hero_card.id
        })

      attrs = %{
        title: "Test with hero",
        hero_id: hero.id
      }

      assert {:ok, deck} = Deck |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert deck.hero_id == hero.id
    end

    test "prevents creating a deck with invalid hero" do
      # Create Hero with incomplete cards (missing alter ego card)
      hero_card = create(Sanctum.Games.Card, attrs: %{base_code: "01001", set: "spider_man"})

      _side =
        create(Sanctum.Games.CardSide,
          attrs: %{
            card_id: hero_card.id,
            name: "Spider-Man",
            type: :hero,
            code: hero_card.code,
            side_identifier: "A",
            is_primary_side: true
          }
        )

      # Create Hero record pointing at a card that is missing its alter ego side
      {:ok, hero} =
        Sanctum.Heroes.find_or_create_hero(%{
          hero_name: "Spider-Man",
          alter_ego_name: "Peter Parker",
          set: "spider_man",
          base_code: hero_card.base_code,
          card_id: hero_card.id
        })

      attrs = %{
        title: "Test with invalid hero",
        hero_id: hero.id
      }

      assert {:error, _} = Deck |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
    end
  end

  test "creates a deck with cards" do
    hero_card = create(Sanctum.Games.Card, attrs: %{base_code: "01002", set: "captain_marvel"})
    # Create hero CardSide
    _side =
      create(Sanctum.Games.CardSide,
        attrs: %{
          card_id: hero_card.id,
          name: "Captain Marvel",
          type: :hero,
          code: hero_card.code,
          side_identifier: "A",
          is_primary_side: true
        }
      )

    alter_ego_card =
      create(Sanctum.Games.Card, attrs: %{base_code: "01002", set: "captain_marvel"})

    # Create alter ego CardSide
    _side =
      create(Sanctum.Games.CardSide,
        attrs: %{
          card_id: alter_ego_card.id,
          name: "Carol Danvers",
          type: :alter_ego,
          code: alter_ego_card.code,
          side_identifier: "B",
          is_primary_side: true
        }
      )

    # Create Hero record
    {:ok, hero} =
      Sanctum.Heroes.find_or_create_hero(%{
        hero_name: "Captain Marvel",
        alter_ego_name: "Carol Danvers",
        set: "captain_marvel",
        base_code: hero_card.base_code,
        card_id: hero_card.id
      })

    cards = create(Sanctum.Games.Card, count: 3)
    card_ids = Enum.map(cards, & &1.id)

    title = "Test with cards"

    assert {:ok, %Deck{title: ^title} = deck} =
             Deck
             |> Ash.Changeset.for_create(:create_with_cards, %{
               card_ids: card_ids,
               title: title,
               hero_id: hero.id
             })
             |> Ash.create(load: [:deck_cards])

    assert length(deck.deck_cards) == 3
  end

  test "re-importing a deck with the same mcdb_id does not duplicate deck cards" do
    hero_card = create(Sanctum.Games.Card, attrs: %{base_code: "01003", set: "she_hulk"})

    _side =
      create(Sanctum.Games.CardSide,
        attrs: %{
          card_id: hero_card.id,
          name: "She-Hulk",
          type: :hero,
          code: hero_card.code,
          side_identifier: "A",
          is_primary_side: true
        }
      )

    alter_ego_card = create(Sanctum.Games.Card, attrs: %{base_code: "01003", set: "she_hulk"})

    _side =
      create(Sanctum.Games.CardSide,
        attrs: %{
          card_id: alter_ego_card.id,
          name: "Jennifer Walters",
          type: :alter_ego,
          code: alter_ego_card.code,
          side_identifier: "B",
          is_primary_side: true
        }
      )

    {:ok, hero} =
      Sanctum.Heroes.find_or_create_hero(%{
        hero_name: "She-Hulk",
        alter_ego_name: "Jennifer Walters",
        set: "she_hulk",
        base_code: hero_card.base_code
      })

    cards = create(Sanctum.Games.Card, count: 3)
    card_ids = Enum.map(cards, & &1.id)
    mcdb_id = "12345"

    import_deck = fn card_ids ->
      Sanctum.Decks.create_with_cards(
        %{
          card_ids: card_ids,
          title: "Re-import test",
          mcdb_id: mcdb_id,
          hero_id: hero.id
        },
        load: [:deck_cards]
      )
    end

    assert {:ok, deck} = import_deck.(card_ids)
    assert length(deck.deck_cards) == 3

    # Re-importing the same deck (same mcdb_id) upserts the deck and should
    # yield exactly the new card list, not doubled.
    assert {:ok, deck} = import_deck.(card_ids)
    assert deck.mcdb_id == mcdb_id
    assert length(deck.deck_cards) == 3

    # A changed card list on re-import replaces the old one entirely.
    new_cards = create(Sanctum.Games.Card, count: 2)
    new_card_ids = Enum.map(new_cards, & &1.id)

    assert {:ok, deck} = import_deck.(new_card_ids)
    assert length(deck.deck_cards) == 2

    reloaded_ids =
      deck.deck_cards
      |> Enum.map(& &1.card_id)
      |> Enum.sort()

    assert reloaded_ids == Enum.sort(new_card_ids)
  end
end
