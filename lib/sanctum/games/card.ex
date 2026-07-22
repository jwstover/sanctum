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

    references do
      # A deleted homebrew project takes its custom cards with it. Indexed —
      # the read policy joins through this FK on every card query.
      reference :homebrew_project, on_delete: :delete, index?: true
    end

    check_constraints do
      # An official row can never point at a project; a custom row can never
      # be orphaned.
      check_constraint :origin,
        name: "cards_origin_project_consistency",
        check: "(origin = 'official') = (homebrew_project_id IS NULL)"
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
    # Official-only by intent — even published homebrew shouldn't pollute the
    # guessing pool (the read policy would otherwise admit it).
    read :guessable do
      prepare build(load: [:primary_side])

      filter expr(
               origin == :official and
                 not is_nil(primary_side.flavor) and primary_side.flavor != ""
             )

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

    # -- Homebrew (custom) cards -------------------------------------------
    # User-scoped through policies — never the authorize?: false system-write
    # paths used by catalog sync. Deliberately NOT accepted: origin, code,
    # base_code, set, pack, card_set_id, pack_id — codes are minted by
    # GenerateCustomCode, and a nil `set` keeps customs out of Scenario's
    # set-string relationships by construction.

    create :create_custom do
      description "Creates a homebrew card inside one of the actor's projects."

      accept [:homebrew_project_id, :deck_limit, :unique, :permanent]

      argument :card_sides, {:array, :map}, allow_nil?: false

      validate present(:homebrew_project_id)

      change set_attribute(:origin, :custom)
      change Sanctum.Games.Changes.GenerateCustomCode
      change manage_relationship(:card_sides, type: :direct_control)
    end

    update :update_custom do
      accept [:deck_limit, :unique, :permanent]
      require_atomic? false
    end

    destroy :destroy_custom do
      require_atomic? false
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Filter policy — non-matching rows are excluded from every read (browse,
    # by_code, by_set, guessable, Ash.get, relationship loads), so other
    # users' private customs are invisible by construction. The checks OR
    # together; they must stay separate — an expr referencing ^actor(:id)
    # collapses to false wholesale under a nil actor, so folding them into
    # one OR expression would hide the entire catalog from anonymous reads.
    # Convention: authorize?: false is reserved for catalog sync/system
    # WRITES; any read using it must carry an explicit origin filter.
    policy action_type(:read) do
      authorize_if expr(origin == :official)
      authorize_if expr(homebrew_project.visibility == :published)
      authorize_if expr(homebrew_project.creator_id == ^actor(:id))
    end

    policy action(:create_custom) do
      authorize_if Sanctum.Homebrew.Checks.ActorOwnsProject
    end

    # Filter checks: someone else's custom (or any official card) is simply
    # not found through these actions.
    policy action([:update_custom, :destroy_custom]) do
      authorize_if expr(origin == :custom and homebrew_project.creator_id == ^actor(:id))
    end

    # Official catalog mutations are admin-only; system writes (sync, deck
    # import) go through Sanctum.MarvelCdb with authorize?: false. Enumerated
    # by action (not action_type) so this policy never also applies to the
    # custom actions above — every applicable policy must pass.
    policy action([:create, :create_with_sides, :update, :update_with_sides, :destroy]) do
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

    # Official catalog card vs. user-created homebrew (Sanctum.Homebrew).
    attribute :origin, Sanctum.Games.CardOrigin,
      public?: true,
      allow_nil?: false,
      default: :official

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

    # Set for :custom origin only (see the origin check constraint).
    belongs_to :homebrew_project, Sanctum.Homebrew.HomebrewProject do
      public? true
      allow_nil? true
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
