defmodule Sanctum.Decks.DeckCard do
  @moduledoc false

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Decks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "deck_cards"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read, create: :*]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
  end

  relationships do
    belongs_to :card, Sanctum.Games.Card do
      public? true
    end

    belongs_to :deck, Sanctum.Decks.Deck do
      public? true
    end
  end
end
