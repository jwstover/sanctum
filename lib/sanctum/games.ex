defmodule Sanctum.Games do
  use Ash.Domain, otp_app: :sanctum, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Sanctum.Games.Card do
      define :create_card, action: :create
      define :get_card_by_code, args: [:code], get?: true, action: :by_code
    end

    resource Sanctum.Games.Game do
      define :create_game, action: :create
      define :get_game, get_by: :id, action: :read
    end
  end
end
