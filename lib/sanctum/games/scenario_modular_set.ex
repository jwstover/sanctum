defmodule Sanctum.Games.ScenarioModularSet do
  @moduledoc """
  Join between a `Scenario` and the modular encounter `CardSet`s it recommends.
  """
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "scenario_modular_sets"
    repo Sanctum.Repo

    references do
      reference :scenario, on_delete: :delete
      reference :card_set, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy, create: :*]
  end

  # Mirrors Scenario's open policy. manage_relationship creates and destroys
  # these rows under the parent action's authorization context.
  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    timestamps()
  end

  relationships do
    belongs_to :scenario, Sanctum.Games.Scenario do
      public? true
      allow_nil? false
    end

    belongs_to :card_set, Sanctum.Catalog.CardSet do
      public? true
      allow_nil? false
    end
  end

  identities do
    identity :unique_scenario_card_set, [:scenario_id, :card_set_id]
  end
end
