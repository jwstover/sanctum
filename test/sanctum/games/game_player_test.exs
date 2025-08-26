defmodule Sanctum.Games.GamePlayerTest do
  use Sanctum.DataCase, async: true

  alias Sanctum.Games

  defp create_test_game_player do
    # Create a unique test user
    email = "test#{:rand.uniform(100000)}@example.com"
    {:ok, user} =
      Sanctum.Accounts.User
      |> Ash.Changeset.for_create(:create, %{
        email: email,
        confirmed_at: DateTime.utc_now()
      })
      |> Ash.create(authorize?: false)

    # Create a scenario with a villain
    set_name = "test_scenario_#{:rand.uniform(100000)}"
    {:ok, scenario} =
      Games.create_scenario(%{
        name: "Test Scenario",
        set: set_name,
        recommended_modular_sets: []
      })

    {:ok, _villain_card} =
      Sanctum.Games.Card
      |> Ash.Changeset.for_create(:create, %{
        name: "Test Villain",
        type: :villain,
        set: set_name,
        code: "testv#{:rand.uniform(100000)}",
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
      assert {:error, %Ash.Error.Invalid{}} = Games.change_health(game_player, %{amount: "not_a_number"}, actor: user)
    end
  end
end