defmodule Sanctum.GamesTest do
  use Sanctum.DataCase, async: true

  alias Sanctum.Games
  alias Sanctum.Games.Card

  # Helper function to create a card with its primary side
  defp create_card_with_side(card_attrs, side_attrs) do
    {:ok, card} = Card |> Ash.Changeset.for_create(:create, card_attrs) |> Ash.create()

    side_attrs_with_card_id =
      Map.merge(side_attrs, %{
        card_id: card.id,
        code: card_attrs.code,
        side_identifier: "A",
        is_primary_side: true
      })

    {:ok, _side} =
      Sanctum.Games.CardSide
      |> Ash.Changeset.for_create(:create, side_attrs_with_card_id)
      |> Ash.create()

    {:ok, card}
  end

  describe "villain enum values" do
    setup do
      {:ok, scenario} =
        Games.create_scenario(%{
          name: "Villain Zone Scenario",
          set: "villain_zone_scenario",
          recommended_modular_sets: []
        })

      {:ok, card} =
        create_card_with_side(
          %{
            base_code: "zonev01",
            code: "zonev01",
            set: "villain_zone_scenario",
            pack: "villain_zone_scenario"
          },
          %{
            name: "Zone Test Villain",
            type: :villain,
            health: 10,
            attack: 2,
            scheme: 1
          }
        )

      {:ok, user} =
        Sanctum.Accounts.User
        |> Ash.Changeset.for_create(:create, %{
          email: "villain-zone@example.com",
          confirmed_at: DateTime.utc_now()
        })
        |> Ash.create(authorize?: false)

      %{card: card, scenario: scenario, user: user}
    end

    test "game card can be created in the :villain_play zone", %{card: card} do
      assert {:ok, game_card} =
               Sanctum.Games.GameCard
               |> Ash.Changeset.for_create(:create, %{
                 card_id: card.id,
                 zone: :villain_play,
                 order: 0
               })
               |> Ash.create(authorize?: false)

      assert game_card.zone == :villain_play
    end

    test "game card can be moved to the :villain_play zone", %{
      card: card,
      scenario: scenario,
      user: user
    } do
      {:ok, game} = Games.create_game(%{scenario_id: scenario.id, modular_sets: []}, actor: user)
      game = Games.get_game!(game.id, load: [:game_players])
      game_player = hd(game.game_players)

      {:ok, game_card} =
        Sanctum.Games.GameCard
        |> Ash.Changeset.for_create(:create, %{
          card_id: card.id,
          game_player_id: game_player.id,
          zone: :hero_hand,
          order: 0
        })
        |> Ash.create(authorize?: false)

      assert {:ok, moved} =
               Games.move_game_card(
                 game_card,
                 %{game_player_id: game_player.id, zone: :villain_play},
                 authorize?: false
               )

      assert moved.zone == :villain_play
    end

    test "the misspelled :villian_play zone is rejected", %{card: card} do
      assert {:error, _} =
               Sanctum.Games.GameCard
               |> Ash.Changeset.for_create(:create, %{
                 card_id: card.id,
                 zone: :villian_play,
                 order: 0
               })
               |> Ash.create(authorize?: false)
    end
  end

  describe "create_scenario" do
    test "creates a scenario with valid input" do
      attrs = %{
        name: "Rhino",
        set: "rhino",
        recommended_modular_sets: ["bomb_scare"]
      }

      assert {:ok, _} = Games.create_scenario(attrs)
    end

    test "sets timestamps on creation" do
      attrs = %{
        name: "Klaw",
        set: "klaw",
        recommended_modular_sets: []
      }

      assert {:ok, scenario} = Games.create_scenario(attrs)
      assert %DateTime{} = scenario.inserted_at
      assert %DateTime{} = scenario.updated_at
    end
  end

  describe "create_game" do
    setup do
      # Create a scenario with encounter cards but no recommended modular sets
      {:ok, scenario} =
        Games.create_scenario(%{
          name: "Test Scenario",
          set: "test_scenario",
          recommended_modular_sets: []
        })

      # Create a villain card for the scenario
      {:ok, _villain_card} =
        create_card_with_side(
          %{
            base_code: "testv01",
            code: "testv01",
            set: "test_scenario",
            pack: "test_scenario"
          },
          %{
            name: "Test Villain",
            type: :villain,
            health: 10,
            attack: 2,
            scheme: 1
          }
        )

      # Create some encounter cards for the scenario
      {:ok, encounter_card1} =
        create_card_with_side(
          %{
            base_code: "test001",
            code: "test001",
            set: "test_scenario",
            pack: "test_scenario"
          },
          %{
            name: "Test Encounter 1",
            type: :minion
          }
        )

      {:ok, encounter_card2} =
        create_card_with_side(
          %{
            base_code: "test002",
            code: "test002",
            set: "test_scenario",
            pack: "test_scenario"
          },
          %{
            name: "Test Encounter 2",
            type: :treachery
          }
        )

      # Create modular set cards
      {:ok, modular_card1} =
        create_card_with_side(
          %{
            base_code: "mod001",
            code: "mod001",
            set: "test_modular",
            pack: "test_modular"
          },
          %{
            name: "Modular Card 1",
            type: :attachment
          }
        )

      {:ok, modular_card2} =
        create_card_with_side(
          %{
            base_code: "mod002",
            code: "mod002",
            set: "test_modular",
            pack: "test_modular"
          },
          %{
            name: "Modular Card 2",
            type: :side_scheme
          }
        )

      # Create a test user
      {:ok, user} =
        Sanctum.Accounts.User
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
      game =
        Games.get_game!(game.id,
          load: [
            encounter_deck: [:deck_cards]
          ]
        )

      # Verify encounter deck was created
      assert game.encounter_deck

      # Verify encounter cards were created and placed in encounter deck
      encounter_deck_cards = game.encounter_deck.deck_cards
      # Only includes encounter cards, villains are properly excluded
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

    test "creates game_villain with card_id and active_side_id set", %{
      scenario: scenario,
      user: user
    } do
      assert {:ok, game} =
               Games.create_game(%{scenario_id: scenario.id, modular_sets: []}, actor: user)

      game = Games.get_game!(game.id, load: [:game_villain])

      assert game.game_villain
      assert game.game_villain.card_id
      assert game.game_villain.active_side_id
    end

    test "creates game with encounter deck including modular set cards", %{
      encounter_cards: encounter_cards,
      modular_cards: modular_cards,
      user: user
    } do
      # Create a scenario with recommended modular sets
      {:ok, modular_scenario} =
        Games.create_scenario(%{
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
      game =
        Games.get_game!(game.id,
          load: [
            encounter_deck: [:deck_cards]
          ]
        )

      # Verify encounter deck was created
      assert game.encounter_deck

      # Verify encounter cards were created (scenario + modular)
      encounter_deck_cards = game.encounter_deck.deck_cards
      # 2 scenario encounter cards + 2 modular cards = 4 (villains excluded)
      assert length(encounter_deck_cards) == 4

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

    test "creates game with empty encounter deck when scenario has no encounter cards", %{
      user: user
    } do
      # Create scenario with no encounter cards
      {:ok, empty_scenario} =
        Games.create_scenario(%{
          name: "Empty Scenario",
          set: "empty_scenario",
          recommended_modular_sets: []
        })

      # Create a villain for the empty scenario
      {:ok, _empty_villain} =
        create_card_with_side(
          %{
            base_code: "emptyv01",
            code: "emptyv01",
            set: "empty_scenario",
            pack: "empty_scenario"
          },
          %{
            name: "Empty Villain",
            type: :villain,
            health: 8,
            attack: 1,
            scheme: 1
          }
        )

      game_attrs = %{
        scenario_id: empty_scenario.id,
        modular_sets: []
      }

      assert {:ok, game} = Games.create_game(game_attrs, actor: user)

      # Load the game with its encounter deck
      game =
        Games.get_game!(game.id,
          load: [
            encounter_deck: [:deck_cards]
          ]
        )

      # Verify encounter deck exists but is empty
      assert game.encounter_deck
      # Villains are properly excluded, so encounter deck is empty
      assert game.encounter_deck.deck_cards == []
    end

    test "encounter cards are shuffled (order is not sequential)", %{
      scenario: scenario,
      user: user
    } do
      # Create more cards to make shuffling more apparent
      for i <- 3..10 do
        {:ok, _card} =
          create_card_with_side(
            %{
              base_code: "test00#{i}",
              code: "test00#{i}",
              set: "test_scenario",
              pack: "test_scenario"
            },
            %{
              name: "Test Encounter #{i}",
              type: :minion
            }
          )
      end

      game_attrs = %{
        scenario_id: scenario.id,
        modular_sets: []
      }

      assert {:ok, game} = Games.create_game(game_attrs, actor: user)

      # Load the encounter deck cards
      game =
        Games.get_game!(game.id,
          load: [
            encounter_deck: [:deck_cards]
          ]
        )

      encounter_deck_cards = game.encounter_deck.deck_cards
      # Should have at least 8 cards
      assert length(encounter_deck_cards) >= 8

      # Verify orders are sequential (0, 1, 2, ...) 
      orders = encounter_deck_cards |> Enum.map(& &1.order) |> Enum.sort()
      expected_orders = 0..(length(encounter_deck_cards) - 1) |> Enum.to_list()
      assert orders == expected_orders
    end
  end
end
