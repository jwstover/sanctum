defmodule Sanctum.Villains.Villain do
  @moduledoc false

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Villains,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "villains"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read, create: :*]

    read :by_set do
      argument :set, :string, allow_nil?: false
      filter expr(set == ^arg(:set))
    end

    create :find_or_create do
      accept [:villain_name, :set]
      upsert? true
      upsert_identity :unique_villain_set
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :villain_name, :string, public?: true, allow_nil?: false
    attribute :set, :string, public?: true, allow_nil?: false

    timestamps()
  end

  relationships do
    has_many :stage_sides, Sanctum.Games.CardSide do
      source_attribute :villain_name
      destination_attribute :name
      filter expr(type == :villain)
    end
  end

  identities do
    identity :unique_villain_set, [:villain_name, :set]
  end
end
