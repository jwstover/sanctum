defmodule Sanctum.Games.Card do
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "cards"
    repo Sanctum.Repo

    custom_indexes do
      index [:set]
      index [:card_set_id]
      index [:pack_id]
    end
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
      pagination offset?: true, default_limit: 50, required?: false
    end

    create :create do
      primary? true

      accept [:*]

      upsert? true
      upsert_identity :unique_marvelcdb_base_code
    end

    create :create_with_sides do
      accept [:*]

      argument :card_sides, {:array, :map}

      change manage_relationship(:card_sides, type: :direct_control)

      upsert? true
      upsert_identity :unique_marvelcdb_base_code
    end

    update :update_with_sides do
      accept [:*]
      require_atomic? false
      argument :card_sides, {:array, :map}

      change manage_relationship(:card_sides, type: :direct_control)
    end

    read :with_sides do
      prepare build(load: [:card_sides, :primary_side])
    end

    # Random-pickable pool for the "Name That Card" guessing game: any card
    # whose primary side has flavor text. Backs SanctumWeb.GuessLive.Play.
    read :guessable do
      prepare build(load: [:primary_side])

      filter expr(not is_nil(primary_side.flavor) and primary_side.flavor != "")

      pagination offset?: true, default_limit: 1, countable: true, required?: false
    end

    read :by_set do
      argument :set, :string, allow_nil?: false
      filter expr(set == ^arg(:set))
    end

    # The set's canonical hero card. Almost every hero set has exactly one
    # hero-sided card; Ironheart's three suit versions are three separate
    # hero-sided cards in one set, so the lowest base_code (the starting
    # suit) is the canonical one.
    read :canonical_hero do
      argument :set, :string, allow_nil?: false

      filter expr(set == ^arg(:set) and exists(card_sides, type == :hero))

      prepare build(sort: [base_code: :asc], limit: 1)
    end

    read :by_code do
      argument :code, :string, allow_nil?: false
      filter expr(base_code == ^arg(:code))
    end

    read :by_pack do
      argument :pack, :string, allow_nil?: false
      filter expr(pack == ^arg(:pack))
    end

    update :update do
      primary? true

      accept [:*]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    # Catalog mutations are admin-only; system writes (sync, deck import)
    # go through Sanctum.MarvelCdb with authorize?: false.
    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:admin, true)
    end
  end

  attributes do
    uuid_primary_key :id

    # Multi-sided card support
    attribute :is_multi_sided, :boolean, public?: true, default: false
    attribute :base_code, :string, public?: true, allow_nil?: false

    # Card-level properties (apply to all sides)
    attribute :deck_limit, :integer, public?: true
    attribute :unique, :boolean, public?: true, default: false
    attribute :permanent, :boolean, public?: true, default: false

    # Primary side code (for compatibility and primary reference)
    attribute :code, :string, public?: true, allow_nil?: false

    # Categorization fields
    attribute :set, :string, public?: true
    attribute :pack, :string, public?: true

    timestamps()
  end

  relationships do
    has_many :card_sides, Sanctum.Games.CardSide do
      source_attribute :id
      destination_attribute :card_id
      public? true
    end

    has_one :primary_side, Sanctum.Games.CardSide do
      destination_attribute :card_id
      public? true
      filter expr(is_primary_side == true)
    end

    has_many :alts, Sanctum.Games.CardAlt do
      destination_attribute :card_id
      public? true
    end

    many_to_many :decks, Sanctum.Decks.Deck, through: Sanctum.Decks.DeckCard

    # Catalog taxonomy FKs (populated during sync). Nullable — player/basic cards
    # have a pack but no card set. The `set`/`pack` strings above are kept for now
    # (Scenario/Hero/Villain joins + game setup still read them); these become the
    # canonical links in a later phase. Named `pack_ref` to avoid colliding with
    # the `pack` string attribute.
    belongs_to :card_set, Sanctum.Catalog.CardSet do
      public? true
      allow_nil? true
    end

    belongs_to :pack_ref, Sanctum.Catalog.Pack do
      public? true
      allow_nil? true
      source_attribute :pack_id
    end

    # Per-user collection overrides (see Sanctum.Collections). Private data —
    # only referenced through the actor-scoped :owned calculations.
    has_many :collection_cards, Sanctum.Collections.CollectionCard do
      destination_attribute :card_id
    end
  end

  calculations do
    # Collection ownership for the requesting user (^actor resolves from the
    # query's actor; nil actor ⇒ false). A card is derived-owned when the user
    # owns the pack of any printing — its own or an alternate's.
    calculate :owned_via_packs,
              :boolean,
              expr(
                exists(pack_ref.collection_packs, user_id == ^actor(:id)) or
                  exists(alts.pack_ref.collection_packs, user_id == ^actor(:id))
              )

    # Effective ownership: a per-card override always beats pack membership,
    # in both directions.
    calculate :owned,
              :boolean,
              expr(
                exists(collection_cards, user_id == ^actor(:id) and status == :owned) or
                  (not exists(collection_cards, user_id == ^actor(:id) and status == :excluded) and
                     (exists(pack_ref.collection_packs, user_id == ^actor(:id)) or
                        exists(alts.pack_ref.collection_packs, user_id == ^actor(:id))))
              )
  end

  identities do
    identity :unique_marvelcdb_code, [:code]
    identity :unique_marvelcdb_base_code, [:base_code]
  end
end
