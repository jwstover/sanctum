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

    references do
      # Deleting a deck takes its card rows with it (native decks are
      # user-deletable from the builder).
      reference :deck, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy, create: :*]

    # Idempotent absolute-quantity write for the deckbuilder: re-setting an
    # existing deck+card row replaces its quantity in place. Quantity 0 is
    # handled by Sanctum.Decks.set_card_quantity/4 (destroys the row instead —
    # an upsert can't delete).
    create :set_quantity do
      accept [:deck_id, :card_id, :quantity]

      upsert? true
      upsert_identity :unique_deck_card
      upsert_fields [:quantity]
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Deck pages (and the public deck browser) load deck_cards anonymously.
    policy action_type(:read) do
      authorize_if always()
    end

    # Writes are reserved for the owner of the parent deck. System paths
    # (imports, :build seeding) run with authorize?: false. Creates can't use
    # a filter check — the row doesn't exist yet — so a custom check resolves
    # the changeset's deck.
    policy action_type(:create) do
      authorize_if Sanctum.Decks.Checks.DeckOwnedByActor
    end

    policy action_type([:update, :destroy]) do
      authorize_if relates_to_actor_via([:deck, :owner])
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
