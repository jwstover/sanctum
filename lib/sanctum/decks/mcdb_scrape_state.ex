defmodule Sanctum.Decks.McdbScrapeState do
  @moduledoc """
  Durable progress record for the one-time MarvelCDB list-page sweep (see
  `Sanctum.Decks.McdbScrape`). It outlives Oban's pruned job rows (completed
  jobs vanish within about a minute) and is visible from every machine, so it
  is the source of truth for `/admin` and for the post-sweep report — not the
  in-memory per-node `Sanctum.DeckSync.Monitor`.

  The cursor that actually drives the sweep lives in the running job's args;
  this row mirrors it after each page so progress survives a redeploy or a
  crash between pages.

  The `singleton` boolean plus its unique identity keep the table to one row:
  every write upserts the same record.
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Decks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "mcdb_scrape_state"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read]

    read :current do
      get? true
    end

    create :put do
      accept [
        :status,
        :sort,
        :page,
        :last_page,
        :rows_seen,
        :matched,
        :unmatched,
        :users_updated,
        :started_at,
        :finished_at,
        :last_error,
        :missing_count
      ]

      upsert? true
      upsert_identity :singleton

      upsert_fields [
        :status,
        :sort,
        :page,
        :last_page,
        :rows_seen,
        :matched,
        :unmatched,
        :users_updated,
        :started_at,
        :finished_at,
        :last_error,
        :missing_count
      ]
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :singleton, :boolean, public?: true, allow_nil?: false, default: true

    attribute :status, :atom, public?: true, constraints: [one_of: [:running, :done, :failed]]
    attribute :sort, :string, public?: true

    # The last page successfully applied.
    attribute :page, :integer, public?: true
    # `last_page` from the most recent parse; it can grow as the sweep runs.
    attribute :last_page, :integer, public?: true

    attribute :rows_seen, :integer, public?: true, allow_nil?: false, default: 0
    attribute :matched, :integer, public?: true, allow_nil?: false, default: 0
    attribute :unmatched, :integer, public?: true, allow_nil?: false, default: 0
    attribute :users_updated, :integer, public?: true, allow_nil?: false, default: 0

    attribute :started_at, :utc_datetime_usec, public?: true
    attribute :finished_at, :utc_datetime_usec, public?: true

    attribute :last_error, :string, public?: true
    # Decklists this sweep never saw, computed at finish.
    attribute :missing_count, :integer, public?: true

    timestamps()
  end

  identities do
    identity :singleton, [:singleton]
  end
end
