defmodule Sanctum.Catalog.Wave do
  @moduledoc """
  A release wave — the top-level grouping of the browse taxonomy.

  Waves are curated community knowledge (MarvelCDB has no cycle/wave concept);
  they are seeded by `Sanctum.Catalog.Curated`. The Core Set is not its own
  wave — it belongs to Wave 1 as a `Pack` with `product_type: :core`.
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "waves"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read]

    create :find_or_create do
      accept [:number, :name]
      upsert? true
      upsert_identity :unique_number
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

    attribute :number, :integer, public?: true, allow_nil?: false
    attribute :name, :string, public?: true, allow_nil?: false

    timestamps()
  end

  relationships do
    has_many :packs, Sanctum.Catalog.Pack do
      public? true
      destination_attribute :wave_id
    end
  end

  identities do
    identity :unique_number, [:number]
  end
end
