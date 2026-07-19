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
      accept [
        :hero_name,
        :alter_ego_name,
        :set,
        :base_code,
        :card_id,
        :colors,
        :primary_color,
        :secondary_color
      ]

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

    # Hero color identity, sourced from MarvelCDB's identity-card `meta.colors`.
    # `colors` is the raw palette; primary/secondary are the derived gradient pair.
    attribute :colors, {:array, :string}, public?: true
    attribute :primary_color, :string, public?: true
    attribute :secondary_color, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :card, Sanctum.Games.Card do
      public? true
      allow_nil? false
    end

    # Size-changing heroes (Ant-Man, Wasp, Angel/Archangel) have two `:hero`
    # sides — a primary form and an alternate form. Sort primary-first so this
    # `has_one` resolves deterministically to the canonical hero side (and to
    # satisfy Ash's `from_many?`/`sort` requirement for multi-match has_one).
    has_one :hero_side, Sanctum.Games.CardSide do
      source_attribute :card_id
      destination_attribute :card_id
      filter expr(type == :hero)
      sort is_primary_side: :desc
    end

    has_one :alter_ego_side, Sanctum.Games.CardSide do
      source_attribute :card_id
      destination_attribute :card_id
      filter expr(type == :alter_ego)
    end

    has_many :cards, Sanctum.Games.Card do
      source_attribute :set
      destination_attribute :set
      filter expr(not exists(card_sides, type in [:hero, :alter_ego, :main_scheme, :villain]))
    end
  end

  identities do
    # A set contains exactly one hero identity, so `set` alone is the key.
    # Ironheart's three suit versions are three hero-sided cards in one set;
    # both hero-creation paths canonicalize to the lowest base_code
    # (MarvelCdb.canonical_hero_card/1) before upserting on this identity.
    identity :unique_hero_set, [:set]
  end
end
