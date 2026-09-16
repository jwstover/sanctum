defmodule Sanctum.Decks.SideDeck do
  @moduledoc """
  A named collection of cards that sits *alongside* a player deck rather than
  being shuffled into it — Doctor Strange's Invocation deck, Storm's Weather
  deck, Hercules' Gift/Labor decks, and so on.

  A `SideDeck` is a plain presentation struct, not an Ash resource. It is the
  single shape both kinds of side deck materialize into so the deck pages can
  render them uniformly:

    * `:builtin` — derived read-only from the hero's kit (`Sanctum.Decks.SideDecks.builtin_for_hero/1`).
      These live in the card catalog as their own `set` (`<hero_set>_<label>_deck`)
      and never enter a deck's `deck_cards`, so there is nothing to store.
    * `:custom` — a future per-deck, user-editable side deck for swap/tech cards
      (not built yet). It will carry `source: :custom, editable?: true` and be
      backed by stored rows, but produces this same struct.

  `cards` are raw `%{card: card, quantity: n}` entries with the card's
  `:primary_side` loaded — the exact shape `SanctumWeb.Components.DeckCards.card_view/2`
  consumes.
  """

  @type card_entry :: %{card: Sanctum.Games.Card.t(), quantity: pos_integer()}

  @type t :: %__MODULE__{
          key: String.t(),
          name: String.t(),
          source: :builtin | :custom,
          editable?: boolean(),
          cards: [card_entry()]
        }

  @enforce_keys [:key, :name, :source, :editable?, :cards]
  defstruct [:key, :name, :source, :editable?, :cards]
end
