defmodule Sanctum.Games.GameEncounterDeck do
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    primary_read_warning?: false

  postgres do
    table "game_encounter_decks"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read, :destroy, update: :*]

    create :create do
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
    uuid_v7_primary_key :id

    timestamps()
  end

  relationships do
    belongs_to :game, Sanctum.Games.Game, public?: true, allow_nil?: false

    has_many :game_cards, Sanctum.Games.GameCard, public?: true

    has_many :deck_cards, Sanctum.Games.GameCard do
      source_attribute :id
      destination_attribute :game_encounter_deck_id
      filter expr(zone == :encounter_deck)
      sort order: :asc
    end

    has_many :facedown_encounter_cards, Sanctum.Games.GameCard do
      source_attribute :id
      destination_attribute :game_encounter_deck_id
      filter expr(zone == :facedown_encounter)
      sort order: :asc
    end

    has_many :discard_cards, Sanctum.Games.GameCard do
      source_attribute :id
      destination_attribute :game_encounter_deck_id
      filter expr(zone == :encounter_discard)
      sort order: :asc
    end
  end
end
