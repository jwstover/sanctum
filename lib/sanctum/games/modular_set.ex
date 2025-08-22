defmodule Sanctum.Games.ModularSet do
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "modular_sets"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:*]
      upsert? true
      upsert_identity :set_code
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
    attribute :set_code, :string, public?: true, allow_nil?: false
  end

  identities do
    identity :set_code, [:set_code]
  end
end
