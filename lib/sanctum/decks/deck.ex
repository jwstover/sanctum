defmodule Sanctum.Decks.Deck do
  @moduledoc false

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Decks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  postgres do
    table "decks"
    repo Sanctum.Repo

    # The public deck browser (`:browse`) filters by hero and aspect and sorts
    # by recency / title / uniqueness over the whole table — at tens of
    # thousands of decks each of those needs an index to avoid a full
    # scan-and-sort per page load.
    custom_indexes do
      index [:hero_id]
      index [:updated_at]
      index [:title]
      index [:aspects], using: "GIN"

      # Matches the `:browse` action's `desc_nils_last` sort so top-N
      # pagination can walk the index directly.
      index ["uniqueness_percentile DESC NULLS LAST"],
        name: "decks_uniqueness_percentile_index"
    end
  end

  actions do
    defaults [:read, :destroy, create: :*]

    # Public deck-browser search: filter by title/hero name, aspect, and hero,
    # with sorting and offset pagination. Backs SanctumWeb.DeckLive.Index.
    read :browse do
      argument :query, :string, allow_nil?: true
      argument :aspect, :string, allow_nil?: true
      argument :hero_id, :string, allow_nil?: true
      argument :sort, :string, allow_nil?: true

      pagination offset?: true, default_limit: 24, countable: true, required?: false

      prepare fn query, _context ->
        require Ash.Query

        search = Ash.Query.get_argument(query, :query)
        aspect = Ash.Query.get_argument(query, :aspect)
        hero_id = Ash.Query.get_argument(query, :hero_id)
        sort = Ash.Query.get_argument(query, :sort)

        query =
          Ash.Query.load(query, [
            :card_row_count,
            :total_card_count,
            :mcdb_user,
            :owner,
            hero: [:display_name, :hero_side, card: [:primary_side]]
          ])

        query =
          if is_binary(search) and String.trim(search) != "" do
            # Bare words search title/hero name; `field op value` terms filter
            # any registered deck field (see Sanctum.Search.DeckFields).
            case Sanctum.Search.compile(search, Sanctum.Search.DeckFields) do
              %{expr: nil} -> query
              %{expr: filter} -> Ash.Query.filter(query, ^filter)
            end
          else
            query
          end

        query =
          cond do
            not is_binary(aspect) or aspect in ["", "all"] ->
              query

            # An empty aspect list is a basic deck.
            aspect == "basic" ->
              Ash.Query.filter(query, fragment("cardinality(?) = 0", aspects))

            true ->
              Ash.Query.filter(query, ^to_enum(aspect) in aspects)
          end

        query =
          if is_binary(hero_id) and hero_id not in ["", "all"] do
            Ash.Query.filter(query, hero_id == ^hero_id)
          else
            query
          end

        case sort do
          "title" ->
            Ash.Query.sort(query, title: :asc)

          # Most-unique first. Unscored decks (nil percentile — e.g. heroes
          # below the min-deck threshold) sort last.
          "unique" ->
            Ash.Query.sort(query, uniqueness_percentile: :desc_nils_last)

          _ ->
            Ash.Query.sort(query, updated_at: :desc)
        end
      end
    end

    update :update do
      primary? true
      accept [:*]
      require_atomic? false
    end

    update :set_mcdb_dates do
      description "Backfills the MarvelCDB provenance dates on an already-imported deck."
      accept [:mcdb_date_creation, :mcdb_date_update]
      require_atomic? false

      # ValidateHero re-fetches the hero (card + sides) per row and rejects
      # heroes without an alter-ego side (e.g. SP//dr) — both wrong for a
      # provenance-only repair of decks that already imported successfully.
      skip_global_validations? true

      # This isn't a local sync: keep updated_at untouched so a backfill
      # doesn't reshuffle the deck browser's recency sort. Force-changing it to
      # its current value doesn't work (Ash prunes equal-value changes, then
      # update_timestamp stamps it anyway); an atomic self-assignment counts as
      # "changing" and so blocks the timestamp while writing a no-op.
      change fn changeset, _context ->
        Ash.Changeset.atomic_update(changeset, :updated_at, Ash.Expr.ref(:updated_at))
      end
    end

    create :create_with_cards do
      description "Upserts an imported deck and replaces its card list. Each slot is %{card_id, quantity, ignore_deck_limit}."
      accept [:*]
      argument :slots, {:array, :map}

      # This action is only reached via MarvelCDB imports, where the hero_id
      # comes from find_or_create_hero on the deck's own hero card — ValidateHero
      # would re-fetch that hero (with card + sides) per deck only to confirm
      # what the import just constructed. Skipping also stops rejecting heroes
      # with no alter-ego flip side (e.g. SP//dr), which the validation requires
      # but MarvelCDB legitimately publishes.
      skip_global_validations? true

      change fn changeset, _context ->
        slots = Ash.Changeset.get_argument(changeset, :slots) || []

        changeset
        |> Ash.Changeset.after_action(fn _changeset, deck ->
          # Remove any existing deck_cards so re-importing the same deck
          # replaces the card list rather than duplicating it.
          Sanctum.Decks.DeckCard
          |> Ash.Query.filter(deck_id == ^deck.id)
          |> Ash.bulk_destroy!(:destroy, %{})

          deck_card_attrs =
            Enum.map(slots, fn slot ->
              %{
                card_id: slot.card_id,
                deck_id: deck.id,
                quantity: Map.get(slot, :quantity, 1),
                ignore_deck_limit: Map.get(slot, :ignore_deck_limit, false)
              }
            end)

          Ash.bulk_create(deck_card_attrs, Sanctum.Decks.DeckCard, :create)

          {:ok, deck}
        end)
      end

      upsert? true
      upsert_identity :unique_mcdb_deck
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  validations do
    validate {Sanctum.Decks.Validations.ValidateHero, []},
      only_when_valid?: true,
      before_action?: true
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :title, :string, public?: true

    attribute :source, Sanctum.Decks.DeckSource,
      public?: true,
      allow_nil?: false,
      default: :native

    # MarvelCDB provenance. `mcdb_type` disambiguates the id space (a deck #1
    # and a decklist #1 are different objects), so the two together identify
    # the source object.
    attribute :mcdb_id, :string, public?: true
    attribute :mcdb_type, Sanctum.Decks.McdbDeckType, public?: true

    # Aspect cards the deck draws from. Empty list = a basic deck.
    attribute :aspects, {:array, Sanctum.Decks.DeckAspect}, public?: true, default: []

    attribute :meta, :map, public?: true
    attribute :tags, :string, public?: true
    attribute :description_md, :string, public?: true
    attribute :version, :string, public?: true

    # MarvelCDB's own creation/update timestamps for the source decklist. These
    # are the author-facing dates (when the deck was published / last edited on
    # MarvelCDB), distinct from `inserted_at`/`updated_at`, which track when we
    # last synced the row locally. Nil for native decks.
    attribute :mcdb_date_creation, :utc_datetime, public?: true
    attribute :mcdb_date_update, :utc_datetime, public?: true

    # Deck uniqueness, precomputed by Sanctum.Decks.ComputeUniquenessWorker.
    # Measures how unlike other decks of the *same hero* this deck's chosen
    # (non-`:hero`) cards are: uniqueness_score 1.0 = no deck shares its picks,
    # 0.0 = an exact clone. `uniqueness_percentile` is the per-hero rank (0-100)
    # used for sorting/badging; `nearest_deck_id` is the closest same-hero deck.
    # Not public? — these are computed internals, never accepted on write.
    attribute :uniqueness_score, :float, public?: false
    attribute :uniqueness_percentile, :integer, public?: false
    attribute :uniqueness_at, :utc_datetime, public?: false
    attribute :nearest_deck_id, :uuid, public?: false

    timestamps()
  end

  relationships do
    has_many :deck_cards, Sanctum.Decks.DeckCard

    many_to_many :cards, Sanctum.Games.Card, through: Sanctum.Decks.DeckCard

    belongs_to :hero, Sanctum.Heroes.Hero do
      allow_nil? false
      public? true
    end

    # Native decks are owned by a Sanctum user; imported decks are attributed
    # to their MarvelCDB author instead.
    belongs_to :owner, Sanctum.Accounts.User do
      public? true
    end

    belongs_to :mcdb_user, Sanctum.Decks.McdbUser do
      public? true
    end
  end

  aggregates do
    count :card_row_count, :deck_cards
    sum :total_card_count, :deck_cards, :quantity
  end

  identities do
    identity :unique_mcdb_deck, [:mcdb_type, :mcdb_id]
  end

  # Safely convert an incoming filter string to an existing atom; unknown
  # values fall back to a sentinel that matches nothing.
  defp to_enum(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> :__invalid__
  end
end
