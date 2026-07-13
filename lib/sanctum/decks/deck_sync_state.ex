defmodule Sanctum.Decks.DeckSyncState do
  @moduledoc """
  Singleton cursor for the incremental decklist sync — tracks the last date
  through which MarvelCDB's published decklists have been imported.

  The `singleton` boolean plus its unique identity keep the table to one row:
  every write upserts the same record.
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Decks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "deck_sync_state"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read]

    read :current do
      get? true
    end

    create :set_last_synced_date do
      accept [:last_synced_date]
      upsert? true
      upsert_identity :singleton
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :last_synced_date, :date, public?: true
    attribute :singleton, :boolean, public?: true, allow_nil?: false, default: true

    timestamps()
  end

  identities do
    identity :singleton, [:singleton]
  end
end
