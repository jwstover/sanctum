defmodule Sanctum.Games.CardType do
  @moduledoc """
  Ash enum for card types
  """

  use Ash.Type.Enum,
    values: [
      :ally,
      :alter_ego,
      :attachment,
      :environment,
      :event,
      :hero,
      :main_scheme,
      :minion,
      :obligation,
      :resource,
      :side_scheme,
      :support,
      :treachery,
      :upgrade,
      :villain
    ]
end
