defmodule Sanctum.Games.Scenario do
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "scenarios"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:*]
      upsert? true
      upsert_identity :unique_set
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
    attribute :set, :string, public?: true, allow_nil?: false
    attribute :recommended_modular_sets, {:array, :string}, public?: true, allow_nil?: false
  end

  relationships do
    has_many :villains, Sanctum.Games.Card do
      source_attribute :set
      destination_attribute :set

      filter expr(type == :villain)
    end

    has_many :main_schemes, Sanctum.Games.Card do
      source_attribute :set
      destination_attribute :set

      filter expr(type == :main_scheme)
    end

    has_many :encounter_cards, Sanctum.Games.Card do
      source_attribute :set
      destination_attribute :set

      filter expr(type != :villain)
      filter expr(type != :main_scheme)
    end
  end

  identities do
    identity :unique_set, [:set]
  end
end
