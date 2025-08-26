defmodule Sanctum.Games.Game do
  @moduledoc false

  alias Sanctum.Games.Changes.SetRecommendedModularSets
  alias Sanctum.Games.Changes.CreateGamePlayer
  alias Sanctum.Games.Changes.CreateGameScheme
  alias Sanctum.Games.Changes.CreateGameVillian
  alias Sanctum.Games.Changes.CreateGameEncounterDeck

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "games"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:*]

      change set_attribute(:state, :setup)
      change SetRecommendedModularSets, only_when_valid?: true
      change CreateGamePlayer, only_when_valid?: true
      change CreateGameScheme, only_when_valid?: true
      change CreateGameVillian, only_when_valid?: true
      change CreateGameEncounterDeck, only_when_valid?: true
    end

    read :read_games_for_user do
      argument :user_id, :uuid, allow_nil?: false
      prepare build(load: [:game_players])
      filter expr(^arg(:user_id) == game_players.user_id)
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :state, :atom,
      constraints: [one_of: [:setup, :player, :villian, :complete]],
      public?: true,
      allow_nil?: false

    attribute :player_order, {:array, :string}, public?: true

    attribute :modular_sets, {:array, :string}, public?: true, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :scenario, Sanctum.Games.Scenario, public?: true, allow_nil?: false

    has_one :game_villian, Sanctum.Games.GameVillian
    has_one :encounter_deck, Sanctum.Games.GameEncounterDeck
    has_many :game_players, Sanctum.Games.GamePlayer
    has_many :game_schemes, Sanctum.Games.GameScheme
  end
end
