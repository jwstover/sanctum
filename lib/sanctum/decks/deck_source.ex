defmodule Sanctum.Decks.DeckSource do
  @moduledoc """
  Where a deck originated: built natively in Sanctum, or imported from
  MarvelCDB.
  """

  use Ash.Type.Enum,
    values: [
      :native,
      :marvelcdb
    ]
end
