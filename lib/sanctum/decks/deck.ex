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

    # Public deck-browser search: an advanced search query (see
    # Sanctum.Search.DeckFields; the filter sheet writes the same syntax)
    # plus sorting and offset pagination. Backs SanctumWeb.DeckLive.Index.
    read :browse do
      argument :query, :string, allow_nil?: true
      argument :sort, :string, allow_nil?: true

      pagination offset?: true, default_limit: 24, countable: true, required?: false

      prepare fn query, _context ->
        require Ash.Query

        search = Ash.Query.get_argument(query, :query)
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

    # Narrow owner-facing updates for the deckbuilder. Both skip ValidateHero
    # (the hero can't change through them, so re-fetching it per write only
    # costs a query and re-rejects alter-ego-less heroes that already exist).
    update :rename do
      accept [:title]
      require_atomic? false
      skip_global_validations? true
    end

    update :set_aspects do
      accept [:aspects]
      require_atomic? false
      skip_global_validations? true
    end

    update :set_description do
      accept [:description_md]
      require_atomic? false
      skip_global_validations? true
    end

    # Deck lifecycle: draft → finalize → publish. Each is a narrow owner
    # action (same policy as the other builder updates) that skips
    # ValidateHero for the same reason :rename does.
    update :finalize do
      require_atomic? false
      skip_global_validations? true
      change set_attribute(:state, :final)
    end

    # Back to draft also withdraws the deck — a published draft isn't a
    # state the phased flow allows.
    update :reopen do
      require_atomic? false
      skip_global_validations? true
      change set_attribute(:state, :draft)
      change set_attribute(:visibility, :private)
    end

    update :publish do
      require_atomic? false
      skip_global_validations? true

      validate attribute_equals(:state, :final) do
        message "finalize the deck before publishing"
      end

      change set_attribute(:visibility, :published)
    end

    update :unpublish do
      require_atomic? false
      skip_global_validations? true
      change set_attribute(:visibility, :private)
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
          # replaces the card list rather than duplicating it. System write:
          # DeckCard's owner policy would reject the actorless import.
          Sanctum.Decks.DeckCard
          |> Ash.Query.filter(deck_id == ^deck.id)
          |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false)

          deck_card_attrs =
            Enum.map(slots, fn slot ->
              %{
                card_id: slot.card_id,
                deck_id: deck.id,
                quantity: Map.get(slot, :quantity, 1),
                ignore_deck_limit: Map.get(slot, :ignore_deck_limit, false)
              }
            end)

          Ash.bulk_create(deck_card_attrs, Sanctum.Decks.DeckCard, :create, authorize?: false)

          {:ok, deck}
        end)
      end

      upsert? true
      upsert_identity :unique_mcdb_deck
    end

    create :build do
      description "Creates a native deck for the signed-in user, seeding the hero's signature cards."
      accept [:title, :hero_id, :aspects]

      change relate_actor(:owner)

      # Native decks start life as a private draft; the owner finalizes and
      # publishes explicitly from the builder.
      change set_attribute(:visibility, :private)
      change set_attribute(:state, :draft)

      change fn changeset, _context ->
        changeset
        |> default_title()
        |> Ash.Changeset.after_action(fn _changeset, deck ->
          deck_card_attrs =
            deck.hero_id
            |> Sanctum.Decks.signature_cards()
            |> Enum.map(&%{deck_id: deck.id, card_id: &1.id, quantity: &1.deck_limit || 1})

          # System write on the owner's behalf; the actor already passed the
          # :build policy.
          Ash.bulk_create!(deck_card_attrs, Sanctum.Decks.DeckCard, :create,
            authorize?: false,
            stop_on_error?: true,
            return_errors?: true
          )

          {:ok, deck}
        end)
      end
    end
  end

  policies do
    # MarvelCDB imports and backfills run actorless from system code
    # (deck sync workers, Release tasks).
    bypass action([:create_with_cards, :set_mcdb_dates]) do
      authorize_if always()
    end

    # Moderation writes only — reads fall through to the visibility policy
    # below, so admins browse like everyone else and never see private decks
    # they don't own. (System reads that need everything use authorize?: false.)
    bypass [actor_attribute_equals(:admin, true), action_type([:create, :update, :destroy])] do
      authorize_if always()
    end

    # The deck browser and deck pages are public — but private decks are
    # visible only to their owner (filter check; system reads run with
    # authorize?: false).
    policy action_type(:read) do
      authorize_if expr(visibility == :published)
      authorize_if expr(owner_id == ^actor(:id))
    end

    policy action(:build) do
      authorize_if actor_present()
    end

    # The bare :create isn't reachable from the UI; tests and seeds use it
    # actorless.
    policy action(:create) do
      authorize_if always()
    end

    policy action_type([:update, :destroy]) do
      authorize_if relates_to_actor_via(:owner)
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

    # Deck lifecycle. Defaults are :published/:final so imported decks (public
    # decklists on MarvelCDB) and pre-existing rows keep their old always-public
    # behavior; the builder's :build action opts new native decks into
    # :private/:draft explicitly.
    attribute :visibility, Sanctum.Decks.DeckVisibility,
      public?: true,
      allow_nil?: false,
      default: :published

    attribute :state, Sanctum.Decks.DeckState,
      public?: true,
      allow_nil?: false,
      default: :final

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

  calculations do
    # Whether the requesting user owns this deck — backs the `mine:` search
    # field (^actor resolves from the query's actor; a nil actor compares
    # owner_id to NULL, which matches nothing rather than everyone's decks).
    calculate :mine, :boolean, expr(owner_id == ^actor(:id))
  end

  aggregates do
    count :card_row_count, :deck_cards
    sum :total_card_count, :deck_cards, :quantity
  end

  identities do
    identity :unique_mcdb_deck, [:mcdb_type, :mcdb_id]
  end

  # Blank titles on :build get "<Hero> Deck".
  defp default_title(changeset) do
    title = Ash.Changeset.get_attribute(changeset, :title)
    hero_id = Ash.Changeset.get_attribute(changeset, :hero_id)

    if (is_nil(title) or String.trim(title) == "") and not is_nil(hero_id) do
      case Ash.get(Sanctum.Heroes.Hero, hero_id, load: [:display_name], authorize?: false) do
        {:ok, hero} ->
          Ash.Changeset.force_change_attribute(changeset, :title, "#{hero.display_name} Deck")

        _not_found ->
          changeset
      end
    else
      changeset
    end
  end
end
