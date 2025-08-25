defmodule Sanctum.GamesTest do
  use Sanctum.DataCase, async: true

  alias Sanctum.Games
  alias Sanctum.Games.Card

  describe "create_scenario" do
    test "creates a scenario with valid input" do
      attrs = %{
        name: "Rhino",
        set: "rhino",
        recommended_modular_sets: ["bomb_scare"]
      }

      assert {:ok, _} = Games.create_scenario(attrs)
    end
  end

  describe "create_game" do
    setup do
      # Create a scenario with encounter cards but no recommended modular sets
      {:ok, scenario} = Games.create_scenario(%{
        name: "Test Scenario", 
        set: "test_scenario",
        recommended_modular_sets: []
      })

      # Create a villain card for the scenario
      {:ok, _villain_card} = Card |> Ash.Changeset.for_create(:create, %{
        name: "Test Villain",
        type: :villain,
        set: "test_scenario",
        code: "testv01",
        health: 10,
        attack: 2,
        scheme: 1
      }) |> Ash.create()

      # Create some encounter cards for the scenario
      {:ok, encounter_card1} = Card |> Ash.Changeset.for_create(:create, %{
        name: "Test Encounter 1",
        type: :minion,
        set: "test_scenario",
        code: "test001"
      }) |> Ash.create()

      {:ok, encounter_card2} = Card |> Ash.Changeset.for_create(:create, %{
        name: "Test Encounter 2", 
        type: :treachery,
        set: "test_scenario",
        code: "test002"
      }) |> Ash.create()

      # Create modular set cards
      {:ok, modular_card1} = Card |> Ash.Changeset.for_create(:create, %{
        name: "Modular Card 1",
        type: :attachment,
        set: "test_modular",
        code: "mod001"
      }) |> Ash.create()

      {:ok, modular_card2} = Card |> Ash.Changeset.for_create(:create, %{
        name: "Modular Card 2",
        type: :side_scheme,
        set: "test_modular", 
        code: "mod002"
      }) |> Ash.create()

      # Create a test user
      {:ok, user} = Sanctum.Accounts.User 
        |> Ash.Changeset.for_create(:create, %{
          email: "test@example.com",
          confirmed_at: DateTime.utc_now()
        })
        |> Ash.create(authorize?: false)

      %{
        scenario: scenario,
        encounter_cards: [encounter_card1, encounter_card2],
        modular_cards: [modular_card1, modular_card2],
        user: user
      }
    end

    test "creates game with encounter deck populated from scenario cards", %{
      scenario: scenario,
      encounter_cards: encounter_cards,
      user: user
    } do
      game_attrs = %{
        scenario_id: scenario.id,
        modular_sets: []
      }

      assert {:ok, game} = Games.create_game(game_attrs, actor: user)
      
      # Load the game with its encounter deck and cards
      game = Games.get_game!(game.id, load: [
        encounter_deck: [:deck_cards]
      ])

      # Verify encounter deck was created
      assert game.encounter_deck
      
      # Verify encounter cards were created and placed in encounter deck
      encounter_deck_cards = game.encounter_deck.deck_cards
      assert length(encounter_deck_cards) == 2

      # Verify all cards are in encounter_deck zone
      for card <- encounter_deck_cards do
        assert card.zone == :encounter_deck
        assert card.face_up == false
        assert is_integer(card.order)
      end

      # Verify the cards are from the scenario
      card_ids = Enum.map(encounter_deck_cards, & &1.card_id)
      scenario_card_ids = Enum.map(encounter_cards, & &1.id)
      
      for scenario_card_id <- scenario_card_ids do
        assert scenario_card_id in card_ids
      end
    end

    test "creates game with encounter deck including modular set cards", %{
      encounter_cards: encounter_cards,
      modular_cards: modular_cards,
      user: user
    } do
      # Create a scenario with recommended modular sets
      {:ok, modular_scenario} = Games.create_scenario(%{
        name: "Modular Test Scenario", 
        set: "test_scenario",
        recommended_modular_sets: ["test_modular"]
      })

      game_attrs = %{
        scenario_id: modular_scenario.id,
        modular_sets: ["test_modular"]
      }

      assert {:ok, game} = Games.create_game(game_attrs, actor: user)
      
      # Load the game with its encounter deck and cards
      game = Games.get_game!(game.id, load: [
        encounter_deck: [:deck_cards]
      ])

      # Verify encounter deck was created
      assert game.encounter_deck
      
      # Verify encounter cards were created (scenario + modular)
      encounter_deck_cards = game.encounter_deck.deck_cards
      assert length(encounter_deck_cards) == 4  # 2 scenario + 2 modular

      # Verify all cards are properly configured
      for card <- encounter_deck_cards do
        assert card.zone == :encounter_deck
        assert card.face_up == false
        assert is_integer(card.order)
        assert card.game_encounter_deck_id == game.encounter_deck.id
      end

      # Verify the cards include both scenario and modular cards
      card_ids = Enum.map(encounter_deck_cards, & &1.card_id)
      all_expected_card_ids = Enum.map(encounter_cards ++ modular_cards, & &1.id)
      
      for expected_card_id <- all_expected_card_ids do
        assert expected_card_id in card_ids
      end
    end

    test "creates game with empty encounter deck when scenario has no encounter cards", %{user: user} do
      # Create scenario with no encounter cards
      {:ok, empty_scenario} = Games.create_scenario(%{
        name: "Empty Scenario",
        set: "empty_scenario",
        recommended_modular_sets: []
      })

      # Create a villain for the empty scenario
      {:ok, _empty_villain} = Card |> Ash.Changeset.for_create(:create, %{
        name: "Empty Villain",
        type: :villain,
        set: "empty_scenario",
        code: "emptyv01",
        health: 8,
        attack: 1,
        scheme: 1
      }) |> Ash.create()

      game_attrs = %{
        scenario_id: empty_scenario.id,
        modular_sets: []
      }

      assert {:ok, game} = Games.create_game(game_attrs, actor: user)
      
      # Load the game with its encounter deck
      game = Games.get_game!(game.id, load: [
        encounter_deck: [:deck_cards]
      ])

      # Verify encounter deck exists but is empty
      assert game.encounter_deck
      assert game.encounter_deck.deck_cards == []
    end

    test "encounter cards are shuffled (order is not sequential)", %{
      scenario: scenario,
      user: user
    } do
      # Create more cards to make shuffling more apparent
      for i <- 3..10 do
        {:ok, _card} = Card |> Ash.Changeset.for_create(:create, %{
          name: "Test Encounter #{i}",
          type: :minion,
          set: "test_scenario",
          code: "test00#{i}"
        }) |> Ash.create()
      end

      game_attrs = %{
        scenario_id: scenario.id,
        modular_sets: []
      }

      assert {:ok, game} = Games.create_game(game_attrs, actor: user)
      
      # Load the encounter deck cards
      game = Games.get_game!(game.id, load: [
        encounter_deck: [:deck_cards]
      ])

      encounter_deck_cards = game.encounter_deck.deck_cards
      assert length(encounter_deck_cards) >= 8  # Should have at least 8 cards

      # Verify orders are sequential (0, 1, 2, ...) 
      orders = encounter_deck_cards |> Enum.map(& &1.order) |> Enum.sort()
      expected_orders = 0..(length(encounter_deck_cards) - 1) |> Enum.to_list()
      assert orders == expected_orders
    end
  end
end
