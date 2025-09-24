defmodule Sanctum.Games.GamePlayerTest do
  use Sanctum.DataCase, async: true

  alias Sanctum.Games

  defp create_test_game_player do
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
    {:ok, _villain_side} =
      Sanctum.Games.CardSide
      |> Ash.Changeset.for_create(:create, %{
        card_id: villain_card.id,
        name: "Test Villain",
        code: villain_code,
        side_identifier: "A",
        is_primary_side: true,
        type: :villain,
        health: 10,
        attack: 2,
        scheme: 1
      })
      |> Ash.create()

    # Create a test game - this automatically creates a GamePlayer
    {:ok, game} = Games.create_game(%{scenario_id: scenario.id, modular_sets: []}, actor: user)

    # Get the automatically created game player and update it with test values
    game_player =
      game
      |> Ash.load!(:game_players, actor: user)
      |> Map.get(:game_players)
      |> List.first()
      |> Ash.Changeset.for_update(:update, %{health: 25, max_health: 30})
      |> Ash.update!(actor: user)

    {user, game, game_player}
  end

  describe "change_health" do
    test "increases health when amount is positive" do
      {user, _game, game_player} = create_test_game_player()
      assert {:ok, updated_player} = Games.change_health(game_player, %{amount: 5}, actor: user)
      assert updated_player.health == 30
    end

    test "decreases health when amount is negative" do
      {user, _game, game_player} = create_test_game_player()
      assert {:ok, updated_player} = Games.change_health(game_player, %{amount: -10}, actor: user)
      assert updated_player.health == 15
    end

    test "allows health to go to zero" do
      {user, _game, game_player} = create_test_game_player()
      assert {:ok, updated_player} = Games.change_health(game_player, %{amount: -25}, actor: user)
      assert updated_player.health == 0
    end

    test "prevents health from going below zero" do
      {user, _game, game_player} = create_test_game_player()
      assert {:ok, updated_player} = Games.change_health(game_player, %{amount: -30}, actor: user)
      assert updated_player.health == 0
    end

    test "caps health at max_health when increasing" do
      {user, _game, game_player} = create_test_game_player()
      assert {:ok, updated_player} = Games.change_health(game_player, %{amount: 10}, actor: user)
      assert updated_player.health == updated_player.max_health
      assert updated_player.health == 30
    end

    test "allows health increase that does not exceed max_health" do
      {user, _game, game_player} = create_test_game_player()
      assert {:ok, updated_player} = Games.change_health(game_player, %{amount: 3}, actor: user)
      assert updated_player.health == 28
      assert updated_player.health < updated_player.max_health
    end

    test "handles zero amount" do
      {user, _game, game_player} = create_test_game_player()
      original_health = game_player.health
      assert {:ok, updated_player} = Games.change_health(game_player, %{amount: 0}, actor: user)
      assert updated_player.health == original_health
    end

    test "requires amount argument" do
      {user, _game, game_player} = create_test_game_player()
      assert {:error, %Ash.Error.Invalid{}} = Games.change_health(game_player, %{}, actor: user)
    end

    test "requires integer amount" do
      {user, _game, game_player} = create_test_game_player()

      assert {:error, %Ash.Error.Invalid{}} =
               Games.change_health(game_player, %{amount: "not_a_number"}, actor: user)
    end
  end

  describe "hand size calculations with new attributes" do
    test "hand_size calculation uses hero_hand_size when in hero form" do
      {user, _game, game_player} = create_test_game_player()

      # Update game player with hand size attributes
      game_player =
        game_player
        |> Ash.Changeset.for_update(:update, %{
          form: :hero,
          hero_hand_size: 5,
          alter_ego_hand_size: 6,
          hand_size_mod: 0
        })
        |> Ash.update!(actor: user)

      # Load with hand_size calculation
      game_player = Sanctum.Games.GamePlayer |> Ash.get!(game_player.id, load: [:hand_size, :max_hand_size], actor: user)

      # Should use hero_hand_size when form is :hero
      assert game_player.form == :hero
      assert game_player.hero_hand_size == 5
      assert game_player.alter_ego_hand_size == 6
      assert game_player.hand_size == 5  # Uses hero_hand_size
      assert game_player.max_hand_size == 5  # 5 + 0 modifier
    end

    test "hand_size calculation uses alter_ego_hand_size when in alter_ego form" do
      {user, _game, game_player} = create_test_game_player()

      # Update game player with hand size attributes in alter_ego form
      game_player =
        game_player
        |> Ash.Changeset.for_update(:update, %{
          form: :alter_ego,
          hero_hand_size: 5,
          alter_ego_hand_size: 6,
          hand_size_mod: 0
        })
        |> Ash.update!(actor: user)

      # Load with hand_size calculation
      game_player = Sanctum.Games.GamePlayer |> Ash.get!(game_player.id, load: [:hand_size, :max_hand_size], actor: user)

      # Should use alter_ego_hand_size when form is :alter_ego
      assert game_player.form == :alter_ego
      assert game_player.hero_hand_size == 5
      assert game_player.alter_ego_hand_size == 6
      assert game_player.hand_size == 6  # Uses alter_ego_hand_size
      assert game_player.max_hand_size == 6  # 6 + 0 modifier
    end

    test "max_hand_size calculation includes hand_size_mod" do
      {user, _game, game_player} = create_test_game_player()

      # Update with hand size modifier
      game_player =
        game_player
        |> Ash.Changeset.for_update(:update, %{
          form: :hero,
          hero_hand_size: 4,
          alter_ego_hand_size: 5,
          hand_size_mod: 2
        })
        |> Ash.update!(actor: user)

      # Load with calculations
      game_player = Sanctum.Games.GamePlayer |> Ash.get!(game_player.id, load: [:hand_size, :max_hand_size], actor: user)

      # Max hand size should include the modifier
      assert game_player.hand_size == 4  # Base hero hand size
      assert game_player.max_hand_size == 6  # 4 + 2 modifier
    end

    test "hand_size calculation handles nil values gracefully" do
      {user, _game, game_player} = create_test_game_player()

      # Leave hand sizes as nil (simulating before deck selection)
      # Just update the form to ensure we're testing the right state
      game_player =
        game_player
        |> Ash.Changeset.for_update(:update, %{form: :hero})
        |> Ash.update!(actor: user)

      # Load with calculations
      game_player = Sanctum.Games.GamePlayer |> Ash.get!(game_player.id, load: [:hand_size, :max_hand_size], actor: user)

      # Should handle nil gracefully
      assert is_nil(game_player.hero_hand_size)
      assert is_nil(game_player.alter_ego_hand_size)
      assert is_nil(game_player.hand_size)
      assert is_nil(game_player.max_hand_size)
    end

    test "flip action changes form and affects hand_size calculation" do
      {user, _game, game_player} = create_test_game_player()

      # Setup with hand sizes in alter_ego form
      game_player =
        game_player
        |> Ash.Changeset.for_update(:update, %{
          form: :alter_ego,
          hero_hand_size: 4,
          alter_ego_hand_size: 7,
          hand_size_mod: 0
        })
        |> Ash.update!(actor: user)

      # Initially should use alter_ego_hand_size
      game_player = Sanctum.Games.GamePlayer |> Ash.get!(game_player.id, load: [:hand_size], actor: user)
      assert game_player.form == :alter_ego
      assert game_player.hand_size == 7

      # Flip to hero form
      {:ok, flipped_player} =
        game_player
        |> Ash.Changeset.for_update(:flip)
        |> Ash.update(actor: user)

      # Should now use hero_hand_size
      flipped_player = Sanctum.Games.GamePlayer |> Ash.get!(flipped_player.id, load: [:hand_size], actor: user)
      assert flipped_player.form == :hero
      assert flipped_player.hand_size == 4
    end

    test "different hand sizes for hero vs alter ego result in different calculations" do
      {user, _game, game_player} = create_test_game_player()

      # Setup with significantly different hand sizes
      game_player =
        game_player
        |> Ash.Changeset.for_update(:update, %{
          form: :hero,
          hero_hand_size: 3,
          alter_ego_hand_size: 8,
          hand_size_mod: 1
        })
        |> Ash.update!(actor: user)

      # In hero form
      game_player = Sanctum.Games.GamePlayer |> Ash.get!(game_player.id, load: [:hand_size, :max_hand_size], actor: user)
      assert game_player.form == :hero
      assert game_player.hand_size == 3
      assert game_player.max_hand_size == 4  # 3 + 1 modifier

      # Flip to alter_ego form
      {:ok, flipped_player} =
        game_player
        |> Ash.Changeset.for_update(:flip)
        |> Ash.update(actor: user)

      # In alter_ego form
      flipped_player = Sanctum.Games.GamePlayer |> Ash.get!(flipped_player.id, load: [:hand_size, :max_hand_size], actor: user)
      assert flipped_player.form == :alter_ego
      assert flipped_player.hand_size == 8
      assert flipped_player.max_hand_size == 9  # 8 + 1 modifier
    end
  end
end
