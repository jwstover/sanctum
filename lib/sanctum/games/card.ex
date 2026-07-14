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

  # Ownership pools and types that belong in the player card pool (deck-buildable
  # cards). Encounter/villain/identity/scheme cards are excluded. Hero signature
  # cards are the `:hero` pool and surface under the "hero" filter. Pool cards are
  # ordinary `:player` cards carrying the `:pool` aspect.
  @player_ownerships [:player, :basic, :hero]
  @player_types [:hero, :alter_ego, :ally, :event, :support, :upgrade, :resource]

  actions do
    defaults [:destroy]

    read :read do
      primary? true
      pagination offset?: true, default_limit: 50, required?: false
    end

    # Public card pool browsing: player cards filtered by name/aspect/type,
    # matched against the primary side. Backs SanctumWeb.CardLive.Pool.
    read :browse do
      argument :query, :string, allow_nil?: true
      argument :aspect, :string, allow_nil?: true
      argument :type, :string, allow_nil?: true

      pagination offset?: true, default_limit: 24, countable: true, required?: false

      prepare fn query, _context ->
        require Ash.Query

        search = Ash.Query.get_argument(query, :query)
        aspect = Ash.Query.get_argument(query, :aspect)
        type = Ash.Query.get_argument(query, :type)

        query =
          query
          |> Ash.Query.load([:primary_side])
          |> Ash.Query.filter(primary_side.type in ^@player_types)
          |> Ash.Query.filter(primary_side.ownership in ^@player_ownerships)
          |> Ash.Query.sort(base_code: :asc)

        query =
          if is_binary(search) and String.trim(search) != "" do
            pattern = "%" <> String.trim(search) <> "%"
            Ash.Query.filter(query, ilike(primary_side.name, ^pattern))
          else
            query
          end

        query =
          cond do
            not is_binary(aspect) or aspect in ["", "all"] ->
              query

            # "hero"/"basic" are ownership pools, not aspects.
            aspect in ["hero", "basic"] ->
              Ash.Query.filter(query, primary_side.ownership == ^to_enum(aspect))

            true ->
              Ash.Query.filter(query, primary_side.aspect == ^to_enum(aspect))
          end

        if is_binary(type) and type not in ["", "all"] do
          Ash.Query.filter(query, primary_side.type == ^to_enum(type))
        else
          query
        end
      end
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
  end

  identities do
    identity :unique_marvelcdb_code, [:code]
    identity :unique_marvelcdb_base_code, [:base_code]
  end

  # Safely convert an incoming filter string to an existing atom; unknown
  # values fall back to a sentinel that matches nothing.
  defp to_enum(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> :__invalid__
  end
end
