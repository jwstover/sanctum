defmodule Sanctum.Games.CardAspect do
  @moduledoc """
  Ash enum for the four player card aspects.

  Only aspect cards carry an aspect; ownership pools (hero signature, basic,
  pool, encounter, campaign) live on `Sanctum.Games.CardOwnership` instead.
  """

  use Ash.Type.Enum,
    values: [
      :aggression,
      :protection,
      :leadership,
      :justice
    ]
end
