defmodule Sanctum.Decks.DeckTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  alias Sanctum.Decks.Deck

  describe "create" do
    test "creates a deck with a hero" do
      hero = create(Sanctum.Games.Card)
      # Create hero CardSide (factory creates hero type by default, but being explicit)
      _side = create(Sanctum.Games.CardSide, attrs: %{
        card_id: hero.id,
        name: "Test Hero",
        type: :hero,
        code: hero.code,
        side_identifier: "A",
        is_primary_side: true
      })

      alter_ego = create(Sanctum.Games.Card)
      # Create alter ego CardSide
      _side = create(Sanctum.Games.CardSide, attrs: %{
        card_id: alter_ego.id,
        name: "Test Alter Ego",
        type: :alter_ego,
        code: alter_ego.code,
        side_identifier: "A",
        is_primary_side: true
      })

      attrs = %{
        title: "Test with hero",
        hero_code: hero.code,
        alter_ego_code: alter_ego.code
      }

      assert {:ok, deck} = Deck |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert deck.hero_code == hero.code
      assert deck.alter_ego_code == alter_ego.code
    end

    test "prevents adding a non-hero card as a hero" do
      # Create a non-hero card (event type)
      event_card = create(Sanctum.Games.Card, attrs: %{})
      # Create a CardSide for the event card with non-hero type
      _side = create(Sanctum.Games.CardSide, attrs: %{
        card_id: event_card.id,
        name: "Test Event",
        type: :event,
        code: event_card.code,
        side_identifier: "A",
        is_primary_side: true
      })

      alter_ego = create(Sanctum.Games.Card)
      # Create hero CardSide for alter ego
      _side = create(Sanctum.Games.CardSide, attrs: %{
        card_id: alter_ego.id,
        name: "Test Hero Alter Ego",
        type: :alter_ego,
        code: alter_ego.code,
        side_identifier: "A",
        is_primary_side: true
      })

      attrs = %{
        title: "Test with non-hero",
        hero_code: event_card.code,
        alter_ego_code: alter_ego.code
      }

      assert {:error, _} = Deck |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
    end
  end

  test "creates a deck with cards" do
    hero = create(Sanctum.Games.Card)
    # Create hero CardSide
    _side = create(Sanctum.Games.CardSide, attrs: %{
      card_id: hero.id,
      name: "Test Hero",
      type: :hero,
      code: hero.code,
      side_identifier: "A",
      is_primary_side: true
    })

    alter_ego = create(Sanctum.Games.Card)
    # Create alter ego CardSide
    _side = create(Sanctum.Games.CardSide, attrs: %{
      card_id: alter_ego.id,
      name: "Test Alter Ego",
      type: :alter_ego,
      code: alter_ego.code,
      side_identifier: "A",
      is_primary_side: true
    })

    cards = create(Sanctum.Games.Card, count: 3)
    card_ids = Enum.map(cards, & &1.id)

    title = "Test with cards"

    assert {:ok, %Deck{title: ^title} = deck} =
             Deck
             |> Ash.Changeset.for_create(:create_with_cards, %{
               card_ids: card_ids,
               title: title,
               hero_code: hero.code,
               alter_ego_code: alter_ego.code
             })
             |> Ash.create(load: [:deck_cards])

    assert length(deck.deck_cards) == 3
  end
end
