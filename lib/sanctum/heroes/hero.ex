defmodule Sanctum.Heroes.Hero do
  @moduledoc false

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Heroes,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "heroes"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read, create: :*]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :hero_name, :string, public?: true
    attribute :alter_ego_name, :string, public?: true
    attribute :set, :string, public?: true

    timestamps()
  end

  relationships do
    has_one :hero_card, Sanctum.Games.Card do
      source_attribute :set
      destination_attribute :set
      filter expr(type == :hero)
    end

    has_one :alter_ego_card, Sanctum.Games.Card do
      source_attribute :set
      destination_attribute :set
      filter expr(type == :alter_ego)
    end

    has_many :cards, Sanctum.Games.Card do
      source_attribute :set
      destination_attribute :set
      filter expr(type not in [:obligation, :hero])
    end
  end
end
