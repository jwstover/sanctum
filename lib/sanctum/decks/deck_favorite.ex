defmodule Sanctum.Decks.DeckFavorite do
  @moduledoc """
  A user's personal bookmark of a deck. Favorites are private — visible to and
  writable by their owner only — and work on any deck the user can see (native
  or imported). Backs the `favorited` calculation on `Deck` and the `favorite:`
  search field.
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Decks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "deck_favorites"
    repo Sanctum.Repo

    references do
      # Drop a user's favorites when the deck goes away (owner deletes a native
      # deck, catalog prune removes an imported one).
      reference :deck, on_delete: :delete
    end

    # The favorite/unfavorite writes and the `favorited` exists-subquery both
    # look up by (user_id, deck_id); the unique identity covers that pair.
    custom_indexes do
      index [:user_id]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :favorite do
      description "Favorite a deck on the current user's behalf. Idempotent."
      accept [:deck_id]
      change relate_actor(:user)

      # Favoriting the same deck twice is a no-op, not an error.
      upsert? true
      upsert_identity :unique_user_deck
    end
  end

  policies do
    # Favorites are private: a user reads, creates, and destroys only their own.
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action(:favorite) do
      authorize_if actor_present()
    end

    policy action_type(:destroy) do
      authorize_if relates_to_actor_via(:user)
    end
  end

  attributes do
    uuid_v7_primary_key :id
    timestamps()
  end

  relationships do
    belongs_to :user, Sanctum.Accounts.User do
      allow_nil? false
      public? true
    end

    belongs_to :deck, Sanctum.Decks.Deck do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_user_deck, [:user_id, :deck_id]
  end
end
