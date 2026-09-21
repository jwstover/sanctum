defmodule Sanctum.GameLog do
  @moduledoc """
  A personal log of physical (in-person) Marvel Champions games — distinct
  from `Sanctum.Games`' live digital game state (the online "smart table").
  Captures just enough about a finished tabletop game to look back on: the
  scenario/villain, modular sets and main scheme in play, and each player's
  hero + aspect.
  """
  use Ash.Domain, otp_app: :sanctum, extensions: [AshAdmin.Domain, AshPhoenix]

  admin do
    show? true
  end

  resources do
    resource Sanctum.GameLog.LoggedGame do
      define :create_logged_game, action: :create
      define :get_logged_game, get_by: :id, action: :read
      define :list_logged_games, action: :for_user
      define :destroy_logged_game, action: :destroy
    end

    resource Sanctum.GameLog.LoggedGamePlayer
  end
end
