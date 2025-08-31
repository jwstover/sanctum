defmodule Sanctum.Games.GameCard do
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Sanctum.Games.Changes.AssignOrder

  postgres do
    table "game_cards"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    read :peek do
      argument :game_player_id, :uuid, allow_nil?: false
      argument :count, :integer, allow_nil?: false
      argument :zone, :atom, default: :hero_deck

      prepare build(sort: [:order], limit: arg(:count))

      filter expr(game_player_id == ^arg(:game_player_id))
      filter expr(zone == ^arg(:zone))
    end

    read :peek_encounter do
      argument :game_encounter_deck_id, :uuid, allow_nil?: false
      argument :count, :integer, allow_nil?: false

      prepare build(sort: [:order], limit: arg(:count))

      filter expr(game_encounter_deck_id == ^arg(:game_encounter_deck_id))
      filter expr(zone == :encounter_deck)
    end

    update :move do
      accept [:game_player_id, :zone]
      require_atomic? false

      change AssignOrder
    end

    update :flip do
      change atomic_update(:face_up, expr(not face_up))
    end

    update :update_counters do
      argument :threat_delta, :integer, default: 0
      argument :damage_delta, :integer, default: 0
      argument :counter_delta, :integer, default: 0

      change atomic_update(:threat, expr(threat + ^arg(:threat_delta)))
      change atomic_update(:damage, expr(damage + ^arg(:damage_delta)))
      change atomic_update(:counter, expr(counter + ^arg(:counter_delta)))
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :zone, :atom,
      public?: true,
      allow_nil?: false,
      constraints: [
        one_of: [
          :hero_deck,
          :hero_hand,
          :hero_discard,
          :hero_play,
          :encounter_deck,
          :encounter_discard,
          :villian_play,
          :facedown_encounter,
          :main_scheme,
          :side_scheme,
          :removed_from_game,
          :victory_display
        ]
      ]

    attribute :order, :integer, public?: true, allow_nil?: false

    attribute :status, :atom,
      constraints: [one_of: [:ready, :exhausted]],
      public?: true,
      default: :ready

    attribute :face_up, :boolean, public?: true, default: false

    attribute :threat, :integer, public?: true, default: 0
    attribute :damage, :integer, public?: true, default: 0
    attribute :counter, :integer, public?: true, default: 0

    timestamps()
  end

  relationships do
    belongs_to :game_player, Sanctum.Games.GamePlayer, public?: true
    belongs_to :game_encounter_deck, Sanctum.Games.GameEncounterDeck, public?: true
    belongs_to :card, Sanctum.Games.Card, public?: true
  end
end
