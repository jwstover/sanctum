defmodule Sanctum.Games do
  use Ash.Domain, otp_app: :sanctum, extensions: [AshAdmin.Domain, AshPhoenix]

  admin do
    show? true
  end

  resources do
    resource Sanctum.Games.Card do
      define :create_card, action: :create
      define :get_card, get_by: :id, action: :read
      define :get_card_by_code, args: [:code], get?: true, action: :by_code
      define :get_cards_by_set, args: [:set], action: :by_set
    end

    resource Sanctum.Games.Game do
      define :create_game, action: :create
      define :get_game, get_by: :id, action: :read
    end

    resource Sanctum.Games.Scenario do
      define :create_scenario, action: :create
      define :get_scenario_by_set, get_by: :set, action: :read
    end
  end
end
