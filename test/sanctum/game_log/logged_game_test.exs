defmodule Sanctum.GameLog.LoggedGameTest do
  use Sanctum.DataCase, async: true

  alias Sanctum.GameLog
  alias Sanctum.Games

  defp uid, do: :rand.uniform(1_000_000)

  defp create_user do
    Sanctum.Accounts.User
    |> Ash.Changeset.for_create(:create, %{
      email: "u#{uid()}@example.com",
      confirmed_at: DateTime.utc_now()
    })
    |> Ash.create!(authorize?: false)
  end

  defp create_card(set, side_attrs) do
    code = "c#{uid()}"

    card =
      Games.Card
      |> Ash.Changeset.for_create(:create, %{base_code: code, code: code, set: set, pack: set})
      |> Ash.create!(authorize?: false)

    Games.CardSide
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(
        %{
          card_id: card.id,
          code: code,
          side_identifier: "A",
          is_primary_side: true,
          name: "Card #{code}"
        },
        side_attrs
      )
    )
    |> Ash.create!(authorize?: false)

    card
  end

  defp create_scenario(main_scheme_count) do
    set = "test_scenario_#{uid()}"

    {:ok, scenario} =
      Games.create_scenario(%{name: "Scenario #{set}", villain_set_id: villain_set!(set).id},
        authorize?: false
      )

    create_card(set, %{type: :villain, name: "Villain #{set}", health: %{value: 10}})

    schemes =
      for i <- 1..main_scheme_count do
        create_card(set, %{type: :main_scheme, name: "Scheme #{i}"})
      end

    {scenario, schemes}
  end

  defp create_hero do
    card = create_card("hero_#{uid()}", %{type: :hero})

    Sanctum.Heroes.create_hero!(
      %{hero_name: "Hero #{uid()}", set: "hero_set_#{uid()}", card_id: card.id},
      authorize?: false
    )
  end

  defp params(scenario, heroes, extra \\ %{}) do
    Map.merge(
      %{
        scenario_id: scenario.id,
        modular_sets: ["bomb_scare"],
        logged_game_players: Enum.map(heroes, &%{hero_id: &1.id, aspect: "justice"})
      },
      extra
    )
  end

  test "derives villain and single main scheme, creates players" do
    user = create_user()
    {scenario, [scheme]} = create_scenario(1)
    heroes = [create_hero(), create_hero()]

    {:ok, game} =
      GameLog.create_logged_game(params(scenario, heroes), actor: user, load: [:villain])

    assert game.villain.villain_name == "Villain #{scenario.set}"
    assert game.main_scheme_id == scheme.id
    assert game.modular_sets == ["bomb_scare"]

    game = Ash.load!(game, :logged_game_players, actor: user)

    assert Enum.map(game.logged_game_players, & &1.hero_id) |> Enum.sort() ==
             Enum.map(heroes, & &1.id) |> Enum.sort()

    assert Enum.all?(game.logged_game_players, &(&1.aspect == "justice"))
  end

  test "requires a main scheme choice when the scenario has several" do
    user = create_user()
    {scenario, _schemes} = create_scenario(2)

    assert {:error, error} =
             GameLog.create_logged_game(params(scenario, [create_hero()]), actor: user)

    assert Exception.message(error) =~ "main scheme"
  end

  test "accepts an explicit main scheme when the scenario has several" do
    user = create_user()
    {scenario, [_, second]} = create_scenario(2)

    {:ok, game} =
      GameLog.create_logged_game(
        params(scenario, [create_hero()], %{main_scheme_id: second.id}),
        actor: user
      )

    assert game.main_scheme_id == second.id
  end

  test "other users cannot read or destroy a logged game; destroy cascades to players" do
    owner = create_user()
    other = create_user()
    {scenario, _} = create_scenario(1)

    {:ok, game} = GameLog.create_logged_game(params(scenario, [create_hero()]), actor: owner)

    assert {:error, _} = GameLog.get_logged_game(game.id, actor: other)
    assert GameLog.list_logged_games!(actor: other) == []

    assert {:error, _} = GameLog.destroy_logged_game(game, actor: other)

    assert :ok = GameLog.destroy_logged_game(game, actor: owner)
    assert Ash.read!(GameLog.LoggedGamePlayer, authorize?: false) == []
  end
end
