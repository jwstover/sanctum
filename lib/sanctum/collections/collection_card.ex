defmodule Sanctum.Collections.CollectionCard do
  @moduledoc """
  A per-card collection override.

  One row per user × canonical card, and only when the user's stated ownership
  deviates from what their packs derive: `:owned` adds a card they don't own a
  pack for; `:excluded` removes a card even though a pack (of any printing)
  would grant it. The override always wins over pack membership.
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Collections,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "collection_cards"
    repo Sanctum.Repo

    references do
      reference :user, on_delete: :delete
      reference :card, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    # Idempotent upsert: re-setting flips the status in place.
    create :set_status do
      accept [:card_id, :status]

      change relate_actor(:user)

      upsert? true
      upsert_identity :unique_user_card
      upsert_fields [:status]
    end

    read :for_user do
      filter expr(user_id == ^actor(:id))
    end
  end

  policies do
    # Collections are private: reads filter to the owner's rows (a nil actor
    # sees nothing), and writes can only relate to the actor.
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action_type(:create) do
      authorize_if relating_to_actor(:user)
    end

    policy action_type([:update, :destroy]) do
      authorize_if relates_to_actor_via(:user)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :status, :atom do
      public? true
      allow_nil? false
      constraints one_of: [:owned, :excluded]
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Sanctum.Accounts.User do
      allow_nil? false
    end

    belongs_to :card, Sanctum.Games.Card do
      public? true
      allow_nil? false
    end
  end

  identities do
    identity :unique_user_card, [:user_id, :card_id]
  end
end
