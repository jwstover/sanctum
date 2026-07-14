defmodule Sanctum.Games.CardSide do
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "card_sides"
    repo Sanctum.Repo
  end

  # Ownership pools and types that belong in the player card pool (deck-buildable
  # cards). Encounter/villain/identity/scheme faces are excluded. Hero signature
  # cards are the `:hero` pool; pool cards are ordinary `:player` cards carrying
  # the `:pool` aspect.
  @player_ownerships [:player, :basic, :hero]
  @player_types [:hero, :alter_ego, :ally, :event, :support, :upgrade, :resource]

  actions do
    defaults [:read, :destroy]

    # Public card pool browsing: player card faces filtered by name/aspect/type.
    # Each side is its own row so multi-sided cards surface every face, and
    # searching an alternate title (e.g. "Peter Parker") ranks that face first.
    # Backs SanctumWeb.CardLive.Pool.
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
          |> Ash.Query.load(:card)
          |> Ash.Query.filter(type in ^@player_types)
          |> Ash.Query.filter(ownership in ^@player_ownerships)
          # Side `code` sorts by base_code across cards and primary-first within
          # a card (the primary side always holds the smallest code).
          |> Ash.Query.sort(code: :asc)

        query =
          if is_binary(search) and String.trim(search) != "" do
            pattern = "%" <> String.trim(search) <> "%"
            Ash.Query.filter(query, ilike(name, ^pattern))
          else
            query
          end

        query =
          cond do
            not is_binary(aspect) or aspect in ["", "all"] ->
              query

            # "hero"/"basic" are ownership pools, not aspects.
            aspect in ["hero", "basic"] ->
              Ash.Query.filter(query, ownership == ^to_enum(aspect))

            true ->
              Ash.Query.filter(query, aspect == ^to_enum(aspect))
          end

        if is_binary(type) and type not in ["", "all"] do
          Ash.Query.filter(query, type == ^to_enum(type))
        else
          query
        end
      end
    end

    create :create do
      primary? true
      accept [:*]
    end

    update :update do
      primary? true
      accept [:*]
    end

    read :primary_sides do
      filter expr(is_primary_side == true)
    end

    read :by_code do
      argument :code, :string, allow_nil?: false
      filter expr(code == ^arg(:code))
    end

    read :by_card_and_side do
      argument :card_id, :uuid, allow_nil?: false
      argument :side_identifier, :string, allow_nil?: false
      filter expr(card_id == ^arg(:card_id) and side_identifier == ^arg(:side_identifier))
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
    uuid_v7_primary_key :id

    # Side identification
    attribute :side_identifier, :string, public?: true, allow_nil?: false
    attribute :is_primary_side, :boolean, public?: true, default: false
    attribute :code, :string, public?: true, allow_nil?: false

    # Core card content
    attribute :name, :string, public?: true, allow_nil?: false
    attribute :subname, :string, public?: true
    attribute :traits, {:array, :string}, public?: true, default: []
    attribute :type, Sanctum.Games.CardType, public?: true, allow_nil?: true

    # `ownership` = which pool the card comes from; `aspect` (one of the player
    # aspects, or nil) is only set for aspect cards.
    attribute :ownership, Sanctum.Games.CardOwnership, public?: true
    attribute :aspect, Sanctum.Games.CardAspect, public?: true

    attribute :text, :string, public?: true
    attribute :flavor, :string, public?: true

    # Combat stats (structured: value / star / scaling / consequential). An
    # ally's consequential damage lives on the relevant stat, not a separate column.
    attribute :attack, Sanctum.Games.Stat, public?: true
    attribute :thwart, Sanctum.Games.Stat, public?: true
    attribute :defense, Sanctum.Games.Stat, public?: true

    attribute :health, Sanctum.Games.Stat, public?: true

    attribute :cost, :integer, public?: true

    # Icons
    attribute :acceleration_icon, :boolean, public?: true, default: false
    attribute :amplify_icon, :boolean, public?: true, default: false
    attribute :crisis_icon, :boolean, public?: true, default: false
    attribute :hazard_icon, :boolean, public?: true, default: false

    # Resource Fields
    attribute :resource_energy_count, :integer, public?: true
    attribute :resource_physical_count, :integer, public?: true
    attribute :resource_mental_count, :integer, public?: true
    attribute :resource_wild_count, :integer, public?: true

    # Hero Fields
    attribute :hand_size, :integer, public?: true
    attribute :recover, Sanctum.Games.Stat, public?: true

    # Villain Fields (health scaling lives in `health.scaling`)
    attribute :stage, :integer, public?: true
    attribute :scheme, :integer, public?: true

    # Scheme Fields (structured: value / star / scaling)
    attribute :base_threat, Sanctum.Games.Stat, public?: true
    attribute :escalation_threat, Sanctum.Games.Stat, public?: true
    attribute :max_threat, Sanctum.Games.Stat, public?: true

    # Encounter Fields
    attribute :boost, :integer, public?: true
    attribute :boost_star, :boolean, public?: true, default: false

    # Image
    attribute :image_url, :string, public?: true, allow_nil?: true

    timestamps()
  end

  relationships do
    belongs_to :card, Sanctum.Games.Card do
      public? true
      allow_nil? false
    end
  end

  identities do
    identity :unique_card_side, [:card_id, :side_identifier]
    identity :unique_code, [:code]
  end

  # Safely convert an incoming filter string to an existing atom; unknown
  # values fall back to a sentinel that matches nothing.
  defp to_enum(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> :__invalid__
  end
end
