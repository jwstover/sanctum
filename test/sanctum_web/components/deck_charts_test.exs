defmodule SanctumWeb.Components.DeckChartsTest do
  use ExUnit.Case, async: true

  alias SanctumWeb.Components.DeckCharts

  # A minimal `DeckCards.card_view/2` shape — only the fields stats/1 reads.
  defp view(attrs) do
    Map.merge(
      %{
        qty: 1,
        permanent: false,
        hero?: false,
        pips: [],
        cost_value: nil,
        aspect_key: :basic,
        type: :event
      },
      Map.new(attrs)
    )
  end

  describe "stats/1" do
    test "counts copies, not rows" do
      stats = DeckCharts.stats([view(qty: 3), view(qty: 2)])

      assert stats.total == 5
    end

    test "excludes permanent cards from every series" do
      permanent =
        view(
          qty: 2,
          permanent: true,
          pips: ["wild"],
          cost_value: 3,
          aspect_key: :justice,
          type: :upgrade
        )

      stats = DeckCharts.stats([permanent, view(qty: 1, cost_value: 1)])

      assert stats.total == 1
      assert Enum.all?(stats.resources, &(&1.hero + &1.other == 0))
      assert Enum.map(stats.aspects, & &1.key) == [:basic]
      assert Enum.map(stats.types, & &1.key) == [:event]
      assert Enum.map(stats.costs, & &1.count) == [0, 1]
    end

    test "counts printed icons per copy and splits hero-card icons out" do
      stats =
        DeckCharts.stats([
          view(qty: 2, pips: ["physical", "physical"]),
          view(qty: 1, pips: ["physical"], hero?: true),
          view(qty: 3, pips: ["wild"])
        ])

      by_key = Map.new(stats.resources, &{&1.key, &1})

      assert by_key[:physical].other == 4
      assert by_key[:physical].hero == 1
      assert by_key[:wild] == %{by_key[:wild] | other: 3}
      assert by_key[:mental].other == 0
    end

    test "always emits all four resources in MarvelCDB's column order" do
      stats = DeckCharts.stats([view(pips: ["mental"])])

      assert Enum.map(stats.resources, & &1.key) == [:physical, :mental, :energy, :wild]
    end

    test "fills cost gaps from zero so the curve dips instead of shortcutting" do
      stats =
        DeckCharts.stats([
          view(cost_value: 0),
          view(qty: 2, cost_value: 3)
        ])

      assert stats.costs == [
               %{cost: 0, count: 1},
               %{cost: 1, count: 0},
               %{cost: 2, count: 0},
               %{cost: 3, count: 2}
             ]
    end

    test "ignores cost X and costless cards in the cost curve" do
      stats =
        DeckCharts.stats([
          # Cost X is stored as -1.
          view(cost_value: -1),
          view(cost_value: nil),
          view(cost_value: 1)
        ])

      assert stats.costs == [%{cost: 0, count: 0}, %{cost: 1, count: 1}]
      assert stats.total == 3
    end

    test "has no cost series when nothing in the deck has a printed cost" do
      assert DeckCharts.stats([view(cost_value: nil)]).costs == []
    end

    test "tallies aspects whether the key arrives as an atom or a string" do
      stats =
        DeckCharts.stats([
          view(qty: 2, aspect_key: :aggression),
          view(qty: 3, aspect_key: "aggression"),
          view(aspect_key: :hero)
        ])

      assert stats.aspects == [
               %{key: :hero, label: "Hero", color: "var(--color-aspect-hero)", count: 1},
               %{
                 key: :aggression,
                 label: "Aggression",
                 color: "var(--color-aspect-aggression)",
                 count: 5
               }
             ]
    end

    # Aspects are data-driven (Sanctum.Games.Aspect), so a homebrew aspect is a
    # key this module has never seen. The donut prints the deck total in its
    # center, so every card has to land in some slice or the parts stop summing
    # to the whole.
    test "buckets an unknown aspect into a labeled grey slice" do
      stats =
        DeckCharts.stats([
          view(qty: 4, aspect_key: :justice),
          view(qty: 2, aspect_key: "chronomancy")
        ])

      assert stats.aspects == [
               %{key: :justice, label: "Justice", color: "var(--color-aspect-justice)", count: 4},
               %{
                 key: "chronomancy",
                 label: "Chronomancy",
                 color: "var(--color-aspect-basic)",
                 count: 2
               }
             ]

      assert Enum.sum_by(stats.aspects, & &1.count) == stats.total
    end

    test "orders type slices canonically and buckets unknown types last" do
      stats =
        DeckCharts.stats([
          view(type: :resource),
          view(type: :ally),
          view(type: :alter_ego),
          view(qty: 4, type: :event)
        ])

      assert Enum.map(stats.types, &{&1.label, &1.count}) == [
               {"Allies", 1},
               {"Events", 4},
               {"Resources", 1},
               {"Alter ego", 1}
             ]
    end

    test "an empty deck yields empty series" do
      stats = DeckCharts.stats([])

      assert stats.total == 0
      assert stats.costs == []
      assert stats.aspects == []
      assert stats.types == []
    end

    test "ignores zero-quantity entries the builder may still hold" do
      assert DeckCharts.stats([view(qty: 0, type: :ally)]).types == []
    end
  end
end
