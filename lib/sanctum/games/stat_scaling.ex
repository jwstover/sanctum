defmodule Sanctum.Games.StatScaling do
  @moduledoc """
  How a stat scales with the number of players.

  Derived at sync time from MarvelCDB's inconsistent per_hero/per_group/fixed
  booleans. The community term is `per_player` (not per_hero).
  """

  use Ash.Type.Enum,
    values: [
      :flat,
      :per_player,
      :per_group
    ]
end
