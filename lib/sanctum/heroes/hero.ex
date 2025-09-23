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

    create :find_or_create do
      accept [:hero_name, :alter_ego_name, :set, :base_code]
      upsert? true
      upsert_identity :unique_hero_set
    end
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
    attribute :base_code, :string, public?: true

    timestamps()
  end

  relationships do
    has_one :card, Sanctum.Games.Card do
      source_attribute :base_code
      destination_attribute :base_code
      filter expr(exists(card_sides, type == :hero and is_primary_side == true))
    end

    has_one :hero_side, Sanctum.Games.CardSide do
      manual {Sanctum.ManualRelationships.HasOneThrough, [through: [:card, :card_sides], filter: [type: :hero, is_primary_side: true]]}
    end

    has_one :alter_ego_side, Sanctum.Games.CardSide do
      manual {Sanctum.ManualRelationships.HasOneThrough, [through: [:card, :card_sides], filter: [type: :alter_ego, is_primary_side: true]]}
    end

    has_many :cards, Sanctum.Games.Card do
      source_attribute :set
      destination_attribute :set
      filter expr(not exists(card_sides, type in [:hero, :alter_ego, :main_scheme, :villain]))
    end
  end

  identities do
    identity :unique_hero_set, [:base_code, :set]
  end
end
