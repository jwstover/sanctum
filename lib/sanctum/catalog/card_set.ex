defmodule Sanctum.Catalog.CardSet do
  @moduledoc """
  A named set of cards within a product — a hero's signature set, a villain set,
  a nemesis set, a modular encounter set, etc. (MarvelCDB's `card_set_code`).

  Hero ↔ nemesis tie: a nemesis set is bound to its hero's set via the
  self-referential `hero_set` relationship. MarvelCDB names every nemesis set
  `<hero_set>_nemesis` (verified across the full catalog), so the link is
  resolved during sync by stripping the suffix. The inverse `nemesis_set` lets a
  hero set reach its nemesis, so the browse page can render them together.
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "card_sets"
    repo Sanctum.Repo

    custom_indexes do
      index [:pack_id]
      index [:hero_set_id]
    end
  end

  actions do
    defaults [:read]

    read :by_code do
      argument :code, :string, allow_nil?: false
      get? true
      filter expr(code == ^arg(:code))
    end

    create :upsert do
      accept [:code, :name, :set_type, :pack_id]

      upsert? true
      upsert_identity :unique_code
      # hero_set_id is linked in a separate pass (:set_hero_set) once all sets
      # exist, so it is not clobbered here.
      upsert_fields [:name, :set_type, :pack_id]
    end

    update :set_hero_set do
      accept [:hero_set_id]
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
    attribute :set_type, Sanctum.Catalog.SetType, public?: true

    timestamps()
  end

  relationships do
    belongs_to :pack, Sanctum.Catalog.Pack do
      public? true
      allow_nil? true
    end

    has_many :cards, Sanctum.Games.Card do
      public? true
      destination_attribute :card_set_id
    end

    # For a nemesis set, the hero set it belongs to.
    belongs_to :hero_set, Sanctum.Catalog.CardSet do
      public? true
      allow_nil? true
    end

    # The inverse: for a hero set, its nemesis set.
    has_one :nemesis_set, Sanctum.Catalog.CardSet do
      public? true
      destination_attribute :hero_set_id
    end
  end

  aggregates do
    count :card_count, :cards
  end

  identities do
    identity :unique_code, [:code]
  end
end
