defmodule Sanctum.Games.GameVillianTest do
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
        code: "testv#{:rand.uniform(100_000)}",
        health: 15,
        attack: 2,
        scheme: 1
      })
      |> Ash.create()

    # Create a test game - this automatically creates a GameVillian
    {:ok, game} = Games.create_game(%{scenario_id: scenario.id, modular_sets: []}, actor: user)

    # Get the automatically created game villain and update it with test values
    game_villain =
      game
      |> Ash.load!(:game_villian, actor: user)
      |> Map.get(:game_villian)
      |> Ash.Changeset.for_update(:update, %{health: 12, max_health: 15})
      |> Ash.update!(actor: user)

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
end
