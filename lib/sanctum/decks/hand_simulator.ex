defmodule Sanctum.Decks.HandSimulator do
  @moduledoc """
  Pure opening-hand simulation for the deck detail page: shuffle the draw
  deck, draw an opening hand, and resolve a single mulligan.

  Per the Rules Reference (Step 15, "Resolve Mulligans"): "Each player may
  discard any number of cards from hand, and then draw up to their starting
  hand size. (Do not shuffle these discarded cards back into their decks at
  this time.)" So mulliganed cards move to a discard pile that never returns
  to the draw pile for the rest of the simulated hand — the unlimited "New
  Hand" reset just calls `new/2` again for a fresh shuffle.

  This module has no knowledge of Ash, LiveView, or the DB — it operates on
  the `DeckCards.card_view/2` maps the deck page already builds, expanding
  each into `qty` individually-selectable copies (`copy_id`), and is safe to
  unit test in isolation.
  """

  @type card :: map()
  @type copy :: map()

  @type t :: %{
          hand: [copy()],
          pile: [copy()],
          discard: [copy()],
          hand_size: pos_integer(),
          mulliganed?: boolean()
        }

  @doc """
  Builds a fresh simulator state from a deck's card views: expands each
  non-permanent view with `qty > 0` into `qty` copies (matching the draw-deck
  rule `DeckCharts.stats/1` uses), shuffles, and draws `hand_size` copies into
  the hand. A draw deck smaller than `hand_size` yields a short hand rather
  than raising (tiny decks, test fixtures).
  """
  @spec new([card()], pos_integer()) :: t()
  def new(card_views, hand_size) when is_integer(hand_size) and hand_size > 0 do
    deck =
      card_views
      |> Enum.filter(&(&1.qty > 0 and not &1.permanent))
      |> Enum.flat_map(&expand_copies/1)
      |> Enum.shuffle()

    {hand, pile} = Enum.split(deck, hand_size)

    %{
      hand: hand,
      pile: pile,
      discard: [],
      hand_size: hand_size,
      mulliganed?: false
    }
  end

  @doc """
  Resolves the one allowed mulligan: moves the copies whose `copy_id` is in
  `copy_ids` from hand to discard (never back into the pile), then draws from
  the pile back up to `hand_size`. A no-op (state returned unchanged) once a
  mulligan has already happened, or when `copy_ids` is empty.
  """
  @spec mulligan(t(), [String.t()]) :: t()
  def mulligan(%{mulliganed?: true} = state, _copy_ids), do: state
  def mulligan(state, []), do: state

  def mulligan(state, copy_ids) do
    ids = MapSet.new(copy_ids)

    {discarded, kept} = Enum.split_with(state.hand, &MapSet.member?(ids, &1.copy_id))

    to_draw = state.hand_size - length(kept)
    {drawn, remaining_pile} = Enum.split(state.pile, max(to_draw, 0))

    %{
      state
      | hand: kept ++ drawn,
        pile: remaining_pile,
        discard: state.discard ++ discarded,
        mulliganed?: true
    }
  end

  defp expand_copies(view) do
    Enum.map(1..view.qty, fn i ->
      Map.put(view, :copy_id, "#{view.card_id}-#{i}")
    end)
  end
end
