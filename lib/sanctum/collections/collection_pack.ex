defmodule Sanctum.Collections.CollectionPack do
  @moduledoc """
  A product (pack/box) in a user's collection.

  One row per user × pack. Owning a pack derives ownership of every card in
  it (see the `:owned` calculation on `Sanctum.Games.Card`); per-card
  deviations live in `CollectionCard`.
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Collections,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "collection_packs"
    repo Sanctum.Repo

    references do
      reference :user, on_delete: :delete
      reference :pack, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    # Idempotent "I own this pack": re-adding an owned pack is a no-op.
    create :add do
      accept [:pack_id]

      change relate_actor(:user)

      upsert? true
      upsert_identity :unique_user_pack
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

    timestamps()
  end

  relationships do
    belongs_to :user, Sanctum.Accounts.User do
      allow_nil? false
    end

    belongs_to :pack, Sanctum.Catalog.Pack do
      public? true
      allow_nil? false
    end
  end

  identities do
    identity :unique_user_pack, [:user_id, :pack_id]
  end
end
