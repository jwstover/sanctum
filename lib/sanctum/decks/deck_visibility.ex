defmodule Sanctum.Decks.DeckVisibility do
  @moduledoc """
  Who can see a deck. `:private` decks are visible only to their owner (and
  admins); `:published` decks appear in the public deck browser and deck pages.
  """

  use Ash.Type.Enum, values: [:private, :published]
end
