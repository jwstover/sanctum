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

    references do
      reference :game, on_delete: :delete, on_update: :update
      reference :game_player, on_delete: :delete, on_update: :update
      reference :game_encounter_deck, on_delete: :delete, on_update: :update
    end

    custom_indexes do
      index [:game_player_id]
      index [:game_encounter_deck_id]
      index [:game_player_id, :zone]
      index [:game_encounter_deck_id, :zone]
    end
  end

  actions do
    defaults [:read, :destroy, update: :*]

    create :create do
      primary? true
      accept [:*]

      change fn changeset, _context ->
        card_id = Ash.Changeset.get_attribute(changeset, :card_id)

        if card_id do
          # Load the card with its sides to set initial active_side
          card = Sanctum.Games.get_card!(card_id, load: [:primary_side])

          if card.primary_side do
            Ash.Changeset.change_attribute(changeset, :active_side_id, card.primary_side.id)
          else
            changeset
          end
        else
          changeset
        end
      end
    end

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
      transaction? true

      change AssignOrder
    end

    update :flip do
      require_atomic? false

      change {Sanctum.Games.Changes.FlipToNextSide, set_face_up: true}
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
          :villain_play,
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
    belongs_to :game, Sanctum.Games.Game do
      public? true
      allow_nil? false
    end

    belongs_to :game_player, Sanctum.Games.GamePlayer, public?: true
    belongs_to :game_encounter_deck, Sanctum.Games.GameEncounterDeck, public?: true
    belongs_to :card, Sanctum.Games.Card, public?: true

    belongs_to :active_side, Sanctum.Games.CardSide do
      public? true
      allow_nil? true
    end
  end
end
