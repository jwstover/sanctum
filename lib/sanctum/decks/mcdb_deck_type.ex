defmodule Sanctum.Decks.McdbDeckType do
  @moduledoc """
  Which MarvelCDB object a `mcdb_id` refers to. `deck` and `decklist` live in
  separate id spaces on MarvelCDB, so the id alone is ambiguous.
  """

  use Ash.Type.Enum,
    values: [
      :decklist,
      :deck
    ]
end
