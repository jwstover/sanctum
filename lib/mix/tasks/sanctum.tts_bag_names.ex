defmodule Mix.Tasks.Sanctum.TtsBagNames do
  @shortdoc "Walks the live catalog through the TTS bag-name resolver"

  @moduledoc """
  Resolves every hero, built-in side deck, and player-deck-eligible card in the
  local catalog through `Sanctum.TTS.BagNames` and reports what it produced.

      mix sanctum.tts_bag_names

  Exits non-zero if any player-deck-eligible card (an official card whose
  primary side is `:player` or `:basic` ownership) fails to produce a
  `(pool, name, subname)` lookup. This checks that the resolver covers the
  catalog without crashing; measuring which names are actually *present in the
  mod's bags* is a separate coverage job.
  """

  use Mix.Task

  require Ash.Query

  alias Sanctum.Decks.SideDecks
  alias Sanctum.TTS.BagNames

  @requirements ["app.start"]

  @impl true
  def run(_argv) do
    {resolved, unresolved} =
      eligible_cards()
      |> Enum.map(&{&1, BagNames.card_lookup(&1)})
      |> Enum.split_with(fn {_card, lookup} -> lookup != nil end)

    report_cards(Enum.map(resolved, fn {_card, lookup} -> lookup end))
    report_heroes()
    report_unresolved(Enum.map(unresolved, fn {card, _lookup} -> card end))
  end

  defp eligible_cards do
    Sanctum.Games.Card
    |> Ash.Query.filter(
      origin == :official and
        exists(card_sides, is_primary_side == true and ownership in [:player, :basic])
    )
    |> Ash.Query.load(:primary_side)
    |> Ash.Query.sort(code: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp report_cards(lookups) do
    by_pool = lookups |> Enum.frequencies_by(& &1.pool) |> Enum.sort()
    with_subtitle = Enum.count(lookups, &(&1.subname != nil))
    distinct = lookups |> Enum.uniq() |> length()

    Mix.shell().info("#{length(lookups)} player-deck-eligible cards resolved:")
    Enum.each(by_pool, fn {pool, n} -> Mix.shell().info("  #{pool}: #{n}") end)

    Mix.shell().info(
      "  #{with_subtitle} carry a real subtitle; #{length(lookups) - distinct} duplicate triples (alt arts / reprints)"
    )
  end

  defp report_heroes do
    heroes = Ash.read!(Sanctum.Heroes.Hero, authorize?: false)
    Mix.shell().info("\n#{length(heroes)} heroes:")

    heroes
    |> Enum.sort_by(& &1.hero_name)
    |> Enum.each(fn hero ->
      %{identity: identity} = BagNames.hero_bag_names(hero)

      side_decks =
        hero
        |> SideDecks.builtin_for_hero()
        |> Enum.map(&"#{&1.key} -> #{inspect(BagNames.side_deck_bag_name(&1))}")

      suffix = if side_decks == [], do: "", else: "  [" <> Enum.join(side_decks, ", ") <> "]"
      Mix.shell().info("  #{identity}#{suffix}")
    end)
  end

  defp report_unresolved([]), do: :ok

  defp report_unresolved(unresolved) do
    Mix.shell().error("\n#{length(unresolved)} eligible cards produced no lookup:")

    Enum.each(unresolved, fn card ->
      side = card.primary_side
      Mix.shell().error("  #{card.code} #{side.name} (#{side.ownership}/#{inspect(side.aspect)})")
    end)

    Mix.raise("TTS bag-name resolution is incomplete (see above)")
  end
end
