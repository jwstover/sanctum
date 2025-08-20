defmodule Sanctum.Decks.DeckTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  alias Sanctum.Decks.Deck

  describe "create" do
    test "creates a deck with a hero" do
      hero = create(Sanctum.Games.Card)

      attrs = %{
        title: "Test with hero",
        hero_code: hero.code
      }

      assert {:ok, deck} = Deck |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert deck.hero_code == hero.code
    end

    test "prevents adding a non-hero card as a hero" do
      card = create(Sanctum.Games.Card, attrs: %{type: :event})

      assert card.type == :event

      attrs = %{
        title: "Test with non-hero",
        hero_code: card.code
      }

      assert {:error, _} = Deck |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
    end
  end

  test "creates a deck with cards" do
    hero = create(Sanctum.Games.Card)
    cards = create(Sanctum.Games.Card, count: 3, attrs: %{type: :event})
    card_ids = Enum.map(cards, & &1.id)

    title = "Test with cards"

    assert {:ok, %Deck{title: ^title} = deck} =
             Deck
             |> Ash.Changeset.for_create(:create_with_cards, %{
               card_ids: card_ids,
               title: title,
               hero_code: hero.code
             })
             |> Ash.create(load: [:deck_cards])

    assert length(deck.deck_cards) == 3
  end
end
