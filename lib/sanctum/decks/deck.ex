defmodule Sanctum.Decks.Deck do
  @moduledoc false

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Decks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "decks"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read, create: :*]

    create :create_with_cards do
      accept [:*]
      argument :card_ids, {:array, :uuid}

      change fn changeset, _context ->
        card_ids = Ash.Changeset.get_argument(changeset, :card_ids) || []

        changeset
        |> Ash.Changeset.after_action(fn changeset, deck ->
          deck_card_attrs =
            Enum.map(card_ids, fn card_id ->
              %{card_id: card_id, deck_id: deck.id}
            end)

          Ash.bulk_create(deck_card_attrs, Sanctum.Decks.DeckCard, :create)

          {:ok, deck}
        end)
      end

      upsert? true
      upsert_identity :unique_mcdb_id
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  validations do
    validate {Sanctum.Decks.Validations.ValidateHeroType, []},
      only_when_valid?: true,
      before_action?: true
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :title, :string, public?: true
    attribute :mcdb_id, :string, public?: true
  end

  relationships do
    has_many :deck_cards, Sanctum.Decks.DeckCard

    many_to_many :cards, Sanctum.Games.Card, through: Sanctum.Decks.DeckCard

    belongs_to :hero, Sanctum.Games.Card do
      allow_nil? false
      public? true
      attribute_type :string
      source_attribute :hero_code
      destination_attribute :code
    end
  end

  identities do
    identity :unique_mcdb_id, [:mcdb_id]
  end
end
