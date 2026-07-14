defmodule Sanctum.Games.CardOwnership do
  @moduledoc """
  Which pool a card belongs to.

  Split out from MarvelCDB's `faction_code`, which overloads ownership
  (`hero`, `encounter`, ...) with the player aspects. Ownership answers
  "where does this card come from"; the separate `aspect` answers "which aspect"
  and is only set for aspect player cards. `pool` is an aspect, not an ownership,
  so it lives on `Sanctum.Games.CardAspect`.
  """

  use Ash.Type.Enum,
    values: [
      :player,
      :basic,
      :hero,
      :encounter,
      :campaign
    ]
end
