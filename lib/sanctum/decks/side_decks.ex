defmodule Sanctum.Decks.SideDecks do
  @moduledoc """
  Resolves the side decks that belong *alongside* a deck — see
  `Sanctum.Decks.SideDeck` for the shape and the builtin/custom distinction.

  Built-in side decks are derived from the card catalog, not stored per deck.
  Every side deck ships as its own `Card.set` named `<hero_set>_<label>_deck`
  (e.g. `doctor_strange_invocation_deck`, `storm_weather_deck`,
  `hercules_gift_deck`). Those cards are `ownership: :hero` but live in a
  *different set* than the hero, so they never land in a MarvelCDB decklist's
  `slots` and are absent from every deck's `deck_cards`. We reconstruct them on
  read by matching the hero's `set` against that naming convention — a hero can
  own more than one (Hercules has two).
  """

  require Ash.Query

  alias Sanctum.Decks.SideDeck

  @doc """
  All side decks for a deck, in render order. Requires the deck's `:hero`
  loaded (with its `set`). Today this is the hero's built-in side decks; the
  future custom side deck will be appended here.
  """
  @spec for_deck(Sanctum.Decks.Deck.t()) :: [SideDeck.t()]
  def for_deck(%{hero: hero}), do: builtin_for_hero(hero)
  def for_deck(_deck), do: []

  @doc """
  The hero's built-in side decks, one per `<hero_set>_*_deck` catalog set,
  ordered by set slug. Returns `[]` for heroes without one.
  """
  @spec builtin_for_hero(Sanctum.Heroes.Hero.t() | nil) :: [SideDeck.t()]
  def builtin_for_hero(%{set: hero_set}) when is_binary(hero_set) do
    prefix = hero_set <> "_"

    Sanctum.Games.Card
    # `\_deck` escapes the underscore so it matches a literal `_deck` suffix.
    # The hero-prefix match is done in Elixir to avoid LIKE treating the
    # underscores inside a hero set (e.g. `doctor_strange`) as wildcards.
    |> Ash.Query.filter(origin == :official and fragment("? LIKE '%\\_deck'", set))
    |> Ash.Query.load(:primary_side)
    |> Ash.Query.sort(code: :asc)
    |> Ash.read!(authorize?: false)
    |> Enum.filter(&String.starts_with?(&1.set, prefix))
    |> Enum.group_by(& &1.set)
    |> Enum.sort_by(fn {set, _cards} -> set end)
    |> Enum.map(fn {set, cards} ->
      %SideDeck{
        key: set,
        name: title_for_set(hero_set, set),
        source: :builtin,
        editable?: false,
        cards: Enum.map(cards, &%{card: &1, quantity: &1.deck_limit || 1})
      }
    end)
  end

  def builtin_for_hero(_hero), do: []

  # `doctor_strange_invocation_deck` (hero `doctor_strange`) -> "Invocation Deck".
  defp title_for_set(hero_set, side_set) do
    label =
      side_set
      |> String.replace_prefix(hero_set <> "_", "")
      |> String.replace_suffix("_deck", "")
      |> String.split("_", trim: true)
      |> Enum.map_join(" ", &String.capitalize/1)

    String.trim("#{label} Deck")
  end
end
