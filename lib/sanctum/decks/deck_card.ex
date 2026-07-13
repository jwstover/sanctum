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
    defaults [:read, :destroy, create: :*]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    # Number of copies of this card in the deck (MarvelCDB `slots` value).
    attribute :quantity, :integer, public?: true, allow_nil?: false, default: 1

    # MarvelCDB `ignoreDeckLimitSlots` — copies that don't count against the
    # card's deck limit.
    attribute :ignore_deck_limit, :boolean, public?: true, allow_nil?: false, default: false
  end

  relationships do
    belongs_to :card, Sanctum.Games.Card do
      public? true
    end

    belongs_to :deck, Sanctum.Decks.Deck do
      public? true
    end
  end

  identities do
    identity :unique_deck_card, [:deck_id, :card_id]
  end
end
