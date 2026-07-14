defmodule Sanctum.Games.CardAspect do
  @moduledoc """
  Ash enum for the five player card aspects.

  `:pool` is a full aspect any hero can build into (it debuted with the Deadpool
  pack but is not tied to that hero). Only aspect cards carry an aspect;
  ownership pools (hero signature, basic, encounter, campaign) live on
  `Sanctum.Games.CardOwnership` instead.
  """

  use Ash.Type.Enum,
    values: [
      :aggression,
      :protection,
      :leadership,
      :justice,
      :pool
    ]
end
