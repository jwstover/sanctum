defmodule Sanctum.Games do
  use Ash.Domain, otp_app: :sanctum, extensions: [AshAdmin.Domain, AshPhoenix]

  # By-id update/destroy interfaces (`get_by: [:id]`) run as a bulk action
  # over a query. The homebrew actions aren't atomic, so allow a full read of
  # the (single) row, and authorize by filter so someone else's record is
  # not-found rather than forbidden — the same as an actor-scoped `Ash.get`.
  @by_id_stream [bulk_options: [allow_stream_with: :full_read, authorize_with: :filter]]

  admin do
    show? true
  end

  resources do
    resource Sanctum.Games.Card do
      define :create_card, action: :create
      define :get_card, get_by: :id, action: :read
      define :get_card_by_code, args: [:code], get?: true, action: :by_code
      define :get_cards_by_set, args: [:set], action: :by_set
      define :canonical_hero_card, args: [:set], get?: true, action: :canonical_hero
      define :list_cards, action: :read

      # Homebrew (custom) cards — user-scoped through policies; pass the actor.
      define :create_custom_card, action: :create_custom

      define :update_custom_card,
        action: :update_custom,
        get_by: [:id],
        default_options: @by_id_stream

      define :destroy_custom_card,
        action: :destroy_custom,
        get_by: [:id],
        default_options: @by_id_stream

      define :pair_custom_cards,
        action: :pair_custom,
        get_by: [:id],
        args: [:donor_card_id],
        default_options: @by_id_stream

      # The split-off card is on the result's `__metadata__.unpaired_card`.
      define :unpair_custom_card,
        action: :unpair_custom,
        get_by: [:id],
        default_options: @by_id_stream

      define :move_custom_card,
        action: :move_to_set,
        get_by: [:id],
        args: [:homebrew_set_id],
        default_options: @by_id_stream

      # Pass a list of cards: one transaction, all or nothing — returns an
      # Ash.BulkResult whose status is :success or :error.
      define :move_custom_cards,
        action: :move_to_set,
        args: [:homebrew_set_id],
        default_options: [
          bulk_options: [
            transaction: :all,
            stop_on_error?: true,
            return_errors?: true,
            allow_stream_with: :full_read,
            authorize_with: :filter
          ]
        ]

      define :list_homebrew_set_cards, action: :for_homebrew_set, args: [:homebrew_set_id]
      define :list_shared_set_cards, action: :for_shared_set, args: [:username, :slug]
      define :list_homebrew_sets_cards, action: :for_homebrew_sets, args: [:homebrew_set_ids]
    end

    resource Sanctum.Games.CardSide do
      define :create_card_side, action: :create
      define :update_card_side, action: :update
      define :get_card_side, get_by: :id, action: :read
      define :get_card_side_by_code, args: [:code], get?: true, action: :by_code
      define :list_card_sides_by_codes, args: [:codes], action: :by_codes

      define :get_card_side_by_card_and_side,
        args: [:card_id, :side_identifier],
        get?: true,
        action: :by_card_and_side
    end

    resource Sanctum.Games.CardAlt do
      define :create_card_alt, action: :create
      define :get_card_alt_by_code, args: [:code], get?: true, action: :by_code
      define :list_card_alts_by_codes, args: [:codes], action: :by_codes

      # Homebrew (custom) alt art — user-scoped through policies; pass the actor.
      define :create_custom_alt, action: :create_custom

      define :declare_custom_alt,
        action: :declare_custom,
        args: [:source_card_id, :target_card_id]

      # The re-created card is on the result's `__metadata__.reverted_card`.
      define :revert_custom_alt,
        action: :revert_custom,
        get_by: [:id],
        default_options: [return_destroyed?: true] ++ @by_id_stream

      define :destroy_custom_alt,
        action: :destroy_custom,
        get_by: [:id],
        default_options: @by_id_stream

      define :list_homebrew_set_alts, action: :for_homebrew_set, args: [:homebrew_set_id]

      define :list_homebrew_project_alts,
        action: :for_homebrew_project,
        args: [:homebrew_project_id]
    end

    resource Sanctum.Games.Aspect do
      define :list_aspects, action: :read
      define :get_aspect, get_by: :key, action: :read
      define :create_aspect, action: :create
    end

    resource Sanctum.Games.Game do
      define :create_game, action: :create
      define :get_game, get_by: :id, action: :read
      define :list_games, action: :read_games_for_user, args: [:user_id]
      define :destroy_game, action: :destroy
    end

    resource Sanctum.Games.Scenario do
      define :create_scenario, action: :create
      define :get_scenario, get_by: :id, action: :read
      define :list_scenarios, action: :read
      define :list_scenarios_for_game_setup, action: :for_game_setup
      define :build_scenario, action: :build
      define :rename_scenario, action: :rename
      define :set_scenario_modular_sets, action: :set_modular_sets
      define :destroy_scenario, action: :destroy
    end

    resource Sanctum.Games.ScenarioModularSet

    resource Sanctum.Games.GamePlayer do
      define :flip_identity, action: :flip
      define :get_game_player, get_by: :game_id, action: :read
      define :select_deck, action: :select_deck
      define :change_health, action: :change_health
    end

    resource Sanctum.Games.GameVillain do
      define :change_villain_health, action: :change_health
      define :advance_villain_stage, action: :advance_stage
      define :flip_villain_stage, action: :flip_stage
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
      define :update_game_card_counters, action: :update_counters
      define :move_game_card, action: :move
      define :flip_card, action: :flip
      define :flip_scheme_card, action: :flip_scheme
    end
  end

  def draw_cards(game_player_id, count, opts \\ []) do
    # `return_notifications?: true` keeps Ash from emitting PubSub notifications
    # while inside our transaction; we collect and send them after it commits.
    move_opts = Keyword.put(opts, :return_notifications?, true)

    {:ok, {moved, notifications}} =
      Sanctum.Repo.transaction(fn ->
        {:ok, cards} = peek_cards(game_player_id, count, :hero_deck, opts)

        Enum.map_reduce(cards, [], fn card, acc ->
          {card, notifications} =
            move_game_card!(
              card,
              %{
                game_player_id: game_player_id,
                zone: :hero_hand
              },
              move_opts
            )

          {card, acc ++ notifications}
        end)
      end)

    Ash.Notifier.notify(notifications)

    moved
  end

  def deal_facedown_encounter_cards(game_encounter_deck_id, count, game_player_id, opts \\ []) do
    move_opts = Keyword.put(opts, :return_notifications?, true)

    {:ok, {moved, notifications}} =
      Sanctum.Repo.transaction(fn ->
        {:ok, cards} = peek_encounter_cards(game_encounter_deck_id, count)

        cards
        |> Enum.with_index()
        |> Enum.map_reduce([], fn {card, _index}, acc ->
          {card, notifications} =
            move_game_card!(
              card,
              %{
                game_player_id: game_player_id,
                zone: :facedown_encounter
              },
              move_opts
            )

          {card, acc ++ notifications}
        end)
      end)

    Ash.Notifier.notify(notifications)

    moved
  end
end
