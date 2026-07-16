defmodule Sanctum.Catalog.Pack do
  @moduledoc """
  A physical product — the Core Set, a hero pack, a scenario pack, or a campaign
  expansion box.

  Two disjoint sets of columns with different owners:

    * **MarvelCDB-sourced** (`name`, `position`, `released_on`, `known_count`,
      `total_count`, `marvelcdb_id`) — refreshed from `/packs/` on every sync via
      `:upsert_from_marvelcdb`, which lists exactly these in `upsert_fields`.
    * **Curated** (`product_type`, `wave_id`) — written only by
      `Sanctum.Catalog.Curated` through `:set_curated`.

  Because the two writers touch disjoint columns, re-running a sync never
  clobbers curated data.
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "packs"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read]

    read :by_code do
      argument :code, :string, allow_nil?: false
      get? true
      filter expr(code == ^arg(:code))
    end

    create :upsert_from_marvelcdb do
      accept [:code, :name, :position, :released_on, :known_count, :total_count, :marvelcdb_id]

      upsert? true
      upsert_identity :unique_code
      # Curated columns (product_type, wave_id) are intentionally omitted so a
      # sync never overwrites them.
      upsert_fields [:name, :position, :released_on, :known_count, :total_count, :marvelcdb_id]
    end

    update :set_curated do
      accept [:product_type, :wave_id]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:admin, true)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :code, :string, public?: true, allow_nil?: false
    attribute :name, :string, public?: true

    # MarvelCDB-sourced release metadata.
    attribute :position, :integer, public?: true
    attribute :released_on, :date, public?: true
    attribute :known_count, :integer, public?: true
    attribute :total_count, :integer, public?: true
    attribute :marvelcdb_id, :integer, public?: true

    # Curated.
    attribute :product_type, Sanctum.Catalog.ProductType, public?: true

    timestamps()
  end

  relationships do
    belongs_to :wave, Sanctum.Catalog.Wave do
      public? true
      allow_nil? true
    end

    has_many :card_sets, Sanctum.Catalog.CardSet do
      public? true
      destination_attribute :pack_id
    end

    has_many :cards, Sanctum.Games.Card do
      public? true
      destination_attribute :pack_id
    end
  end

  aggregates do
    # Total physical cards in the product: each card counted once (multi-sided
    # cards are a single Card row), but including its duplicate copies.
    sum :card_total, :cards, :deck_limit
  end

  identities do
    identity :unique_code, [:code]
  end
end
