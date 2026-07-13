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
  end

  actions do
    defaults [:read, :destroy, create: :*]

    update :update do
      primary? true
      accept [:*]
      require_atomic? false
    end

    create :create_with_cards do
      description "Upserts an imported deck and replaces its card list. Each slot is %{card_id, quantity, ignore_deck_limit}."
      accept [:*]
      argument :slots, {:array, :map}

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
end
