defmodule Sanctum.Games do
  use Ash.Domain, otp_app: :sanctum, extensions: [AshAdmin.Domain, AshPhoenix]

  admin do
    show? true
  end

  resources do
    resource Sanctum.Games.Card do
      define :create_card, action: :create
      define :get_card, get_by: :id, action: :read
      define :get_card_by_code, args: [:code], get?: true, action: :by_code
      define :get_cards_by_set, args: [:set], action: :by_set
    end

    resource Sanctum.Games.Game do
      define :create_game, action: :create
      define :get_game, get_by: :id, action: :read
      define :list_games, action: :read_games_for_user, args: [:user_id]
    end

    resource Sanctum.Games.Scenario do
      define :create_scenario, action: :create
      define :get_scenario, get_by: :id, action: :read
      define :get_scenario_by_set, get_by: :set, action: :read
      define :list_scenarios, action: :read
    end

    resource Sanctum.Games.ModularSet do
      define :create_modular_set, action: :create
    end

    resource Sanctum.Games.GamePlayer do
      define :flip_identity, action: :flip
      define :get_game_player, get_by: :game_id, action: :read
      define :select_deck, action: :select_deck
      define :change_health, action: :change_health
    end

    resource Sanctum.Games.GameVillian do
      define :change_villain_health, action: :change_health
    end

    resource Sanctum.Games.GameScheme do
      define :get_game_scheme, get_by: :id, action: :read
      define :update_scheme_threat, args: [:delta], action: :update_threat
      define :update_scheme_counter, args: [:delta], action: :update_counter
    end

    resource Sanctum.Games.GameEncounterDeck

    resource Sanctum.Games.GameCard do
      define :list_game_cards, action: :read
      define :get_game_card, get_by: :id, action: :read
      define :peek_cards, action: :peek, args: [:game_player_id, :count, {:optional, :zone}]

      define :peek_encounter_cards,
        action: :peek_encounter,
        args: [:game_encounter_deck_id, :count]

      define :update_game_card, action: :update
      define :move_game_card, action: :move
      define :flip_card, action: :flip
    end
  end

  def draw_cards(game_player_id, count, opts \\ []) do
    {:ok, cards} = peek_cards(game_player_id, count, :hero_deck, opts)

    cards
    |> Enum.map(fn card ->
      card
      |> move_game_card!(
        %{
          game_player_id: game_player_id,
          zone: :hero_hand
        },
        opts
      )
    end)
  end

  def deal_facedown_encounter_cards(game_encounter_deck_id, count, game_player_id, opts \\ []) do
    {:ok, cards} = peek_encounter_cards(game_encounter_deck_id, count)

    cards
    |> Enum.with_index()
    |> Enum.map(fn {card, _index} ->
      card
      |> move_game_card!(
        %{
          game_player_id: game_player_id,
          zone: :facedown_encounter
        },
        opts
      )
    end)
  end
end
