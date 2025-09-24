defmodule Sanctum.Games.GameVillainTest do
  use Sanctum.DataCase, async: true

  alias Sanctum.Games

  defp create_test_game_villain do
    # Create a unique test user
    email = "test#{:rand.uniform(100_000)}@example.com"

    {:ok, user} =
      Sanctum.Accounts.User
      |> Ash.Changeset.for_create(:create, %{
        email: email,
        confirmed_at: DateTime.utc_now()
      })
      |> Ash.create(authorize?: false)

    # Create a scenario with a villain
    set_name = "test_scenario_#{:rand.uniform(100_000)}"
    villain_name = "Test Villain"

    {:ok, scenario} =
      Games.create_scenario(%{
        name: "Test Scenario",
        set: set_name,
        recommended_modular_sets: []
      })

    villain_code = "testv#{:rand.uniform(100_000)}"

    {:ok, villain_card} =
      Sanctum.Games.Card
      |> Ash.Changeset.for_create(:create, %{
        base_code: villain_code,
        code: villain_code,
        set: set_name,
        pack: set_name
      })
      |> Ash.create()

    # Create the villain card side
    {:ok, villain_side} =
      Sanctum.Games.CardSide
      |> Ash.Changeset.for_create(:create, %{
        card_id: villain_card.id,
        name: villain_name,
        code: villain_code,
        side_identifier: "A",
        is_primary_side: true,
        type: :villain,
        stage: 1,
        health: 15,
        attack: 2,
        scheme: 1
      })
      |> Ash.create()

    # Create the Villain resource
    {:ok, villain} =
      Sanctum.Villains.find_or_create_villain(%{
        villain_name: villain_name,
        set: set_name
      })

    # Create a test game with manually created GameVillain
    {:ok, game} = Games.create_game(%{scenario_id: scenario.id, modular_sets: []}, actor: user)

    # Create the GameVillain manually since the old automatic creation won't work
    {:ok, game_villain} =
      Sanctum.Games.GameVillain
      |> Ash.Changeset.for_create(:create, %{
        game_id: game.id,
        villain_id: villain.id,
        active_stage_card_id: villain_card.id,
        active_stage_side_id: villain_side.id,
        health: 12,
        max_health: 15,
        attack: 2,
        scheme: 1
      })
      |> Ash.create(actor: user)

    {user, game, game_villain}
  end

  describe "change_health" do
    test "increases health when amount is positive" do
      {user, _game, game_villain} = create_test_game_villain()

      assert {:ok, updated_villain} =
               Games.change_villain_health(game_villain, %{amount: 2}, actor: user)

      assert updated_villain.health == 14
    end

    test "decreases health when amount is negative" do
      {user, _game, game_villain} = create_test_game_villain()

      assert {:ok, updated_villain} =
               Games.change_villain_health(game_villain, %{amount: -5}, actor: user)

      assert updated_villain.health == 7
    end

    test "allows health to go to zero" do
      {user, _game, game_villain} = create_test_game_villain()

      assert {:ok, updated_villain} =
               Games.change_villain_health(game_villain, %{amount: -12}, actor: user)

      assert updated_villain.health == 0
    end

    test "prevents health from going below zero" do
      {user, _game, game_villain} = create_test_game_villain()

      assert {:ok, updated_villain} =
               Games.change_villain_health(game_villain, %{amount: -20}, actor: user)

      assert updated_villain.health == 0
    end

    test "caps health at max_health when increasing" do
      {user, _game, game_villain} = create_test_game_villain()

      assert {:ok, updated_villain} =
               Games.change_villain_health(game_villain, %{amount: 10}, actor: user)

      assert updated_villain.health == updated_villain.max_health
      assert updated_villain.health == 15
    end

    test "allows health increase that does not exceed max_health" do
      {user, _game, game_villain} = create_test_game_villain()

      assert {:ok, updated_villain} =
               Games.change_villain_health(game_villain, %{amount: 2}, actor: user)

      assert updated_villain.health == 14
      assert updated_villain.health < updated_villain.max_health
    end

    test "handles zero amount" do
      {user, _game, game_villain} = create_test_game_villain()
      original_health = game_villain.health

      assert {:ok, updated_villain} =
               Games.change_villain_health(game_villain, %{amount: 0}, actor: user)

      assert updated_villain.health == original_health
    end

    test "requires amount argument" do
      {user, _game, game_villain} = create_test_game_villain()

      assert {:error, %Ash.Error.Invalid{}} =
               Games.change_villain_health(game_villain, %{}, actor: user)
    end

    test "requires integer amount" do
      {user, _game, game_villain} = create_test_game_villain()

      assert {:error, %Ash.Error.Invalid{}} =
               Games.change_villain_health(game_villain, %{amount: "not_a_number"}, actor: user)
    end
  end

  describe "multi-stage functionality" do
    defp create_multi_stage_villain do
      # Create a unique test user
      email = "test#{:rand.uniform(100_000)}@example.com"

      {:ok, user} =
        Sanctum.Accounts.User
        |> Ash.Changeset.for_create(:create, %{
          email: email,
          confirmed_at: DateTime.utc_now()
        })
        |> Ash.create(authorize?: false)

      set_name = "test_multi_stage_#{:rand.uniform(100_000)}"
      villain_name = "Multi-Stage Villain"

      # Create stage 1 card and side
      {:ok, stage1_card} =
        Sanctum.Games.Card
        |> Ash.Changeset.for_create(:create, %{
          base_code: "stage1",
          code: "stage1",
          set: set_name,
          pack: set_name
        })
        |> Ash.create()

      {:ok, stage1_side} =
        Sanctum.Games.CardSide
        |> Ash.Changeset.for_create(:create, %{
          card_id: stage1_card.id,
          name: villain_name,
          code: "stage1",
          side_identifier: "A",
          is_primary_side: true,
          type: :villain,
          stage: 1,
          health: 10,
          attack: 1,
          scheme: 1
        })
        |> Ash.create()

      # Create stage 2 card and side
      {:ok, stage2_card} =
        Sanctum.Games.Card
        |> Ash.Changeset.for_create(:create, %{
          base_code: "stage2",
          code: "stage2",
          set: set_name,
          pack: set_name
        })
        |> Ash.create()

      {:ok, stage2_side} =
        Sanctum.Games.CardSide
        |> Ash.Changeset.for_create(:create, %{
          card_id: stage2_card.id,
          name: villain_name,
          code: "stage2",
          side_identifier: "A",
          is_primary_side: true,
          type: :villain,
          stage: 2,
          health: 15,
          attack: 2,
          scheme: 2
        })
        |> Ash.create()

      # Create stage 3 card and side
      {:ok, stage3_card} =
        Sanctum.Games.Card
        |> Ash.Changeset.for_create(:create, %{
          base_code: "stage3",
          code: "stage3",
          set: set_name,
          pack: set_name
        })
        |> Ash.create()

      {:ok, stage3_side} =
        Sanctum.Games.CardSide
        |> Ash.Changeset.for_create(:create, %{
          card_id: stage3_card.id,
          name: villain_name,
          code: "stage3",
          side_identifier: "A",
          is_primary_side: true,
          type: :villain,
          stage: 3,
          health: 20,
          attack: 3,
          scheme: 3
        })
        |> Ash.create()

      # Create the Villain resource
      {:ok, villain} =
        Sanctum.Villains.find_or_create_villain(%{
          villain_name: villain_name,
          set: set_name
        })

      # Create scenario and game
      {:ok, scenario} =
        Games.create_scenario(%{
          name: "Multi Stage Test",
          set: set_name,
          recommended_modular_sets: []
        })

      {:ok, game} = Games.create_game(%{scenario_id: scenario.id, modular_sets: []}, actor: user)

      # Create GameVillain starting at stage 1
      {:ok, game_villain} =
        Sanctum.Games.GameVillain
        |> Ash.Changeset.for_create(:create, %{
          game_id: game.id,
          villain_id: villain.id,
          active_stage_card_id: stage1_card.id,
          active_stage_side_id: stage1_side.id,
          health: 10,
          max_health: 10,
          attack: 1,
          scheme: 1
        })
        |> Ash.create(actor: user)

      {user, game_villain,
       %{
         stage1: %{card: stage1_card, side: stage1_side},
         stage2: %{card: stage2_card, side: stage2_side},
         stage3: %{card: stage3_card, side: stage3_side}
       }}
    end

    test "advances from stage 1 to stage 2" do
      {user, game_villain, stages} = create_multi_stage_villain()

      assert game_villain.active_stage_side_id == stages.stage1.side.id

      {:ok, advanced_villain} = Games.advance_villain_stage(game_villain, actor: user)

      assert advanced_villain.active_stage_side_id == stages.stage2.side.id
      assert advanced_villain.active_stage_card_id == stages.stage2.card.id
    end

    test "advances from stage 2 to stage 3" do
      {user, game_villain, stages} = create_multi_stage_villain()

      # Advance to stage 2 first
      {:ok, stage2_villain} = Games.advance_villain_stage(game_villain, actor: user)

      # Then advance to stage 3
      {:ok, stage3_villain} = Games.advance_villain_stage(stage2_villain, actor: user)

      assert stage3_villain.active_stage_side_id == stages.stage3.side.id
      assert stage3_villain.active_stage_card_id == stages.stage3.card.id
    end

    test "does not advance beyond final stage" do
      {user, game_villain, _stages} = create_multi_stage_villain()

      # Advance to stage 2
      {:ok, stage2_villain} = Games.advance_villain_stage(game_villain, actor: user)
      # Advance to stage 3
      {:ok, stage3_villain} = Games.advance_villain_stage(stage2_villain, actor: user)

      # Try to advance beyond stage 3 - should remain at stage 3
      {:ok, final_villain} = Games.advance_villain_stage(stage3_villain, actor: user)

      assert final_villain.active_stage_side_id == stage3_villain.active_stage_side_id
      assert final_villain.active_stage_card_id == stage3_villain.active_stage_card_id
    end

    test "flip_stage works with FlipToNextSide change module" do
      {user, game_villain, _stages} = create_multi_stage_villain()

      # Add a B side to stage 1 card for flipping test
      stage1_card_id = game_villain.active_stage_card_id

      {:ok, stage1_b_side} =
        Sanctum.Games.CardSide
        |> Ash.Changeset.for_create(:create, %{
          card_id: stage1_card_id,
          name: "Multi-Stage Villain (Flipped)",
          code: "stage1b",
          side_identifier: "B",
          is_primary_side: false,
          type: :villain,
          stage: 1,
          health: 12,
          attack: 2,
          scheme: 1
        })
        |> Ash.create()

      # Now flip the stage
      {:ok, flipped_villain} = Games.flip_villain_stage(game_villain, actor: user)

      assert flipped_villain.active_stage_side_id == stage1_b_side.id
      # Same card, different side
      assert flipped_villain.active_stage_card_id == stage1_card_id
    end
  end
end
