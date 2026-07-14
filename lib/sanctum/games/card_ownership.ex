defmodule Sanctum.Games.CardOwnership do
  @moduledoc """
  Which pool a card belongs to.

  Split out from MarvelCDB's `faction_code`, which overloads ownership
  (`hero`, `encounter`, ...) with the four player aspects. Ownership answers
  "where does this card come from"; the separate `aspect` answers "which aspect"
  and is only set for aspect player cards.
  """

  use Ash.Type.Enum,
    values: [
      :player,
      :basic,
      :pool,
      :hero,
      :encounter,
      :campaign
    ]
end
