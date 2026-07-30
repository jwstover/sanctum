defmodule SanctumWeb.Components.DeckCardsTest do
  use ExUnit.Case, async: true

  alias Sanctum.Decks.SideDeck
  alias SanctumWeb.Components.DeckCards

  # A card shaped just enough for `card_view/2` — plain maps, since card_view
  # only does map access (no struct enforcement).
  defp card(name, attrs \\ []) do
    side =
      Map.merge(
        %{
          name: name,
          cost: 1,
          type: :support,
          ownership: :hero,
          aspect: nil,
          resource_energy_count: 0,
          resource_mental_count: 0,
          resource_physical_count: 0,
          resource_wild_count: 0,
          image_url: "https://example.test/#{name}.png"
        },
        Map.new(Keyword.get(attrs, :side, []))
      )

    %{
      id: Keyword.get(attrs, :id, name),
      primary_side: side,
      permanent: Keyword.get(attrs, :permanent, false),
      unique: false,
      deck_limit: 1
    }
  end

  defp side_deck(cards, attrs \\ []) do
    %SideDeck{
      key: Keyword.get(attrs, :key, "storm_weather_deck"),
      name: Keyword.get(attrs, :name, "Weather Deck"),
      source: Keyword.get(attrs, :source, :builtin),
      editable?: Keyword.get(attrs, :editable?, false),
      cards: cards
    }
  end

  describe "side_deck_views/2" do
    test "sums quantities into count and carries metadata through" do
      sd =
        side_deck([
          %{card: card("Blizzard"), quantity: 1},
          %{card: card("Hurricane"), quantity: 2}
        ])

      [view] = DeckCards.side_deck_views([sd], {nil, nil})

      assert view.key == "storm_weather_deck"
      assert view.name == "Weather Deck"
      assert view.source == :builtin
      assert view.editable? == false
      assert view.count == 3
    end

    test "sorts cards case-insensitively by name" do
      sd =
        side_deck([
          %{card: card("Thunderstorm"), quantity: 1},
          %{card: card("Blizzard"), quantity: 1},
          %{card: card("clear skies"), quantity: 1}
        ])

      [view] = DeckCards.side_deck_views([sd], {nil, nil})

      assert Enum.map(view.cards, & &1.name) == ["Blizzard", "clear skies", "Thunderstorm"]
    end

    test "paints hero-owned side-deck cards with the hero gradient" do
      sd = side_deck([%{card: card("Blizzard"), quantity: 1}])

      [%{cards: [c]}] = DeckCards.side_deck_views([sd], {"#111", "#222"})

      assert c.aspect_key == :hero
      assert c.gradient_from == "#111"
      assert c.gradient_to == "#222"
    end

    test "preserves order and independence across multiple side decks" do
      gifts = side_deck([%{card: card("Sword of Peleus"), quantity: 1}], name: "Gift Deck")
      labors = side_deck([%{card: card("Protect Humanity"), quantity: 1}], name: "Labor Deck")

      views = DeckCards.side_deck_views([gifts, labors], {nil, nil})

      assert Enum.map(views, & &1.name) == ["Gift Deck", "Labor Deck"]
    end

    test "an empty list yields no views" do
      assert DeckCards.side_deck_views([], {nil, nil}) == []
    end
  end
end
