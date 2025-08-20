defmodule Sanctum.Games.CardAspect do
  @moduledoc """
  Ash enum for card aspects
  """

  use Ash.Type.Enum,
    values: [
      :aggression,
      :basic,
      :encounter,
      :hero,
      :villain,
      :protection,
      :leadership,
      :justice,
      :pool
    ]
end
