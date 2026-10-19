defmodule SanctumWeb.Components.ScenarioCardsTest do
  use ExUnit.Case, async: true

  alias SanctumWeb.Components.ScenarioCards

  # Plain maps shaped just enough for the stats helpers (map access only).
  defp card(code, type, attrs \\ []) do
    %{
      code: code,
      deck_limit: Keyword.get(attrs, :deck_limit, 1),
      primary_side:
        Map.merge(
          %{name: code, type: type, image_url: nil, boost: nil},
          Map.new(Keyword.get(attrs, :side, []))
        )
    }
  end

  defp card_set(cards, code \\ "set"), do: %{name: code, code: code, cards: cards}

  describe "combined_stats/1" do
    test "weights the card count and average boost by deck_limit" do
      set =
        card_set([
          card("01", :treachery, deck_limit: 3, side: [boost: 2]),
          card("02", :minion, side: [boost: 0])
        ])

      stats = ScenarioCards.combined_stats([set])

      assert stats.cards == 4
      assert stats.avg_boost == 1.5
      assert stats.type_counts == %{treachery: 3, minion: 1}
    end

    test "treats a nil deck_limit as 1 and a nil boost as 0" do
      set =
        card_set([
          card("01", :treachery, deck_limit: nil, side: [boost: 3]),
          card("02", :minion, side: [boost: nil])
        ])

      assert %{cards: 2, avg_boost: 1.5} = ScenarioCards.combined_stats([set])
    end

    test "ignores boost_star" do
      set = card_set([card("01", :treachery, side: [boost: nil, boost_star: true])])

      assert %{cards: 1, avg_boost: +0.0} = ScenarioCards.combined_stats([set])
    end

    test "leaves villain and main-scheme cards out" do
      set =
        card_set([
          card("01", :villain, side: [boost: 5]),
          card("02", :main_scheme, side: [boost: 5]),
          card("03", :minion, side: [boost: 1])
        ])

      assert %{cards: 1, avg_boost: 1.0} = ScenarioCards.combined_stats([set])
    end

    test "counts card types beyond the stat tiles" do
      set = card_set([card("01", :ally, side: [boost: 2])])

      assert %{cards: 1, avg_boost: 2.0, type_counts: %{}} = ScenarioCards.combined_stats([set])
    end

    test "combines several sets and drops nil entries" do
      a = card_set([card("01", :minion, side: [boost: 1])], "a")
      b = card_set([card("02", :treachery, side: [boost: 3])], "b")

      assert %{cards: 2, avg_boost: 2.0} = ScenarioCards.combined_stats([nil, a, b])
    end

    test "an empty set has no average boost" do
      assert %{cards: 0, avg_boost: nil} = ScenarioCards.combined_stats([card_set([])])
      assert %{cards: 0, avg_boost: nil} = ScenarioCards.combined_stats([nil])
    end
  end

  describe "encounter_set_view/1" do
    test "includes the set's own stats" do
      set = card_set([card("01", :minion, deck_limit: 2, side: [boost: 1])])

      assert %{stats: %{cards: 2, avg_boost: 1.0}} = ScenarioCards.encounter_set_view(set)
    end
  end

  describe "format_boost/1" do
    test "renders a dash for nil" do
      assert ScenarioCards.format_boost(nil) == "—"
    end

    test "renders one decimal" do
      assert ScenarioCards.format_boost(1.4285) == "1.4"
      assert ScenarioCards.format_boost(2.0) == "2.0"
      assert ScenarioCards.format_boost(1) == "1.0"
    end
  end
end
