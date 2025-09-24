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
    end
  end

  actions do
    defaults [:read, :destroy]

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

    read :by_set do
      argument :set, :string, allow_nil?: false
      filter expr(set == ^arg(:set))
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
    policy always() do
      authorize_if always()
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

    many_to_many :decks, Sanctum.Decks.Deck, through: Sanctum.Decks.DeckCard
  end

  identities do
    identity :unique_marvelcdb_code, [:code]
    identity :unique_marvelcdb_base_code, [:base_code]
  end
end
