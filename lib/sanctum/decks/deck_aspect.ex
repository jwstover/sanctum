defmodule Sanctum.Decks.DeckAspect do
  @moduledoc """
  Aspects a deck draws its aspect cards from. A basic deck (no aspect cards)
  is represented as an empty list, so `:basic` is intentionally not a value.
  """

  use Ash.Type.Enum,
    values: [
      :aggression,
      :justice,
      :leadership,
      :protection,
      :pool
    ]
end
