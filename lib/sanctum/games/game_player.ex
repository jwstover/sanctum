defmodule Sanctum.Games.GamePlayer do
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    primary_read_warning?: false

  alias Sanctum.ManualRelationships.HasOneThrough
  alias Sanctum.Games.Changes.SetGameCards

  postgres do
    table "game_players"
    repo Sanctum.Repo
  end

  actions do
    read :read do
      primary? true
      filter expr(user_id == ^actor(:id))
    end

    create :create do
      primary? true
      accept [:*]
    end

    update :select_deck do
      accept [:deck_id]
      require_atomic? false

      change SetGameCards
    end

    update :flip do
      require_atomic? false

      change fn changeset, _context ->
        case Ash.Changeset.fetch_attribute(changeset, :form) do
          {:ok, :alter_ego} -> Ash.Changeset.change_attribute(changeset, :form, :hero)
          {:ok, :hero} -> Ash.Changeset.change_attribute(changeset, :form, :alter_ego)
          _ -> changeset
        end
      end
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :form, :atom,
      constraints: [one_of: [:hero, :alter_ego]],
      public?: true,
      default: :alter_ego

    attribute :health, :integer, public?: true
    attribute :max_health, :integer, public?: true

    attribute :hand_size_mod, :integer, public?: true, default: 0

    timestamps()
  end

  relationships do
    belongs_to :user, Sanctum.Accounts.User, public?: true, allow_nil?: false
    belongs_to :game, Sanctum.Games.Game, public?: true, allow_nil?: false
    belongs_to :deck, Sanctum.Decks.Deck, public?: true

    has_one :hero_card, Sanctum.Games.Card do
      manual {HasOneThrough, [through: [:deck, :hero]]}
    end

    has_many :game_cards, Sanctum.Games.GameCard, public?: true

    has_many :deck_cards, Sanctum.Games.GameCard do
      source_attribute :id
      destination_attribute :game_player_id
      filter expr(zone == :hero_deck)
      sort [order: :asc]
    end

    has_many :hero_play_cards, Sanctum.Games.GameCard do
      source_attribute :id
      destination_attribute :game_player_id
      filter expr(zone == :hero_play)
      sort [order: :asc]
    end

    has_many :hand_cards, Sanctum.Games.GameCard do
      source_attribute :id
      destination_attribute :game_player_id
      filter expr(zone == :hero_hand)
      sort [order: :asc]
    end

    has_many :hero_discard, Sanctum.Games.GameCard do
      source_attribute :id
      destination_attribute :game_player_id
      filter expr(zone == :hero_discard)
      sort [order: :asc]
    end
  end

  calculations do
    calculate :hand_size,
              :integer,
              expr(if form == :hero, do: deck.hero.hand_size, else: deck.alter_ego.hand_size),
              load: [deck: [:hero, :alter_ego]]

    calculate :current_hand_size, :integer, expr(count(hand_cards)), load: [:hand_cards]
    calculate :max_hand_size, :integer, expr(hand_size + hand_size_mod), load: [:hand_size]
  end

  identities do
    identity :unique_game_id_user_id, [:user_id, :game_id]
  end
end
