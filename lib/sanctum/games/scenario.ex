defmodule Sanctum.Games.Scenario do
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "scenarios"
    repo Sanctum.Repo

    identity_wheres_to_sql unique_official_villain_set: "owner_id IS NULL"

    references do
      reference :owner, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :villain_set_id]
      upsert? true
      upsert_identity :unique_official_villain_set

      argument :modular_sets, {:array, :uuid}

      validate Sanctum.Games.Validations.ValidateVillainSet
      change Sanctum.Games.Changes.SetScenarioSet, only_when_valid?: true
      change manage_relationship(:modular_sets, type: :append_and_remove)
    end
  end

  policies do
    # Catalog writes are admin-only; seeds and tests use authorize?: false.
    bypass [actor_attribute_equals(:admin, true), action_type([:create, :update, :destroy])] do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
    # Derived from villain_set.code; kept as a column for the Card.set joins below.
    attribute :set, :string, public?: true, allow_nil?: false

    timestamps()
  end

  relationships do
    # The villain CardSet, not Villains.Villain: sets like Loki, Marauders and
    # Sinister Six have several Villain rows each.
    belongs_to :villain_set, Sanctum.Catalog.CardSet do
      public? true
      allow_nil? false
    end

    # nil = official scenario.
    belongs_to :owner, Sanctum.Accounts.User do
      public? true
      allow_nil? true
    end

    many_to_many :modular_sets, Sanctum.Catalog.CardSet do
      public? true
      through Sanctum.Games.ScenarioModularSet
      source_attribute_on_join_resource :scenario_id
      destination_attribute_on_join_resource :card_set_id
    end

    has_many :villains, Sanctum.Games.Card do
      source_attribute :set
      destination_attribute :set
      filter expr(primary_side.type == :villain)
    end

    has_many :main_schemes, Sanctum.Games.Card do
      source_attribute :set
      destination_attribute :set
      filter expr(primary_side.type == :main_scheme)
    end

    has_many :encounter_cards, Sanctum.Games.Card do
      source_attribute :set
      destination_attribute :set
      filter expr(primary_side.type not in [:villain, :main_scheme])
    end
  end

  identities do
    # One official scenario per villain set; user-owned scenarios may share a set.
    identity :unique_official_villain_set, [:villain_set_id] do
      where expr(is_nil(owner_id))
    end
  end
end
