defmodule SanctumWeb.GameLive.IndexTest do
  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias Sanctum.Games

  defp create_test_game(user) do
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
      |> Ash.create(authorize?: false)

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
        health: %{value: 10},
        attack: %{value: 2},
        scheme: 1
      })
      |> Ash.create(authorize?: false)

    # Create a main scheme card and side
    scheme_code = "tests#{:rand.uniform(100_000)}"

    {:ok, scheme_card} =
      Sanctum.Games.Card
      |> Ash.Changeset.for_create(:create, %{
        base_code: scheme_code,
        code: scheme_code,
        set: set_name,
        pack: set_name
      })
      |> Ash.create(authorize?: false)

    {:ok, _scheme_side} =
      Sanctum.Games.CardSide
      |> Ash.Changeset.for_create(:create, %{
        card_id: scheme_card.id,
        name: "Test Scheme",
        code: scheme_code,
        side_identifier: "A",
        is_primary_side: true,
        type: :main_scheme,
        base_threat: %{value: 5},
        escalation_threat: %{value: 1}
      })
      |> Ash.create(authorize?: false)

    # Create a test game using Games.create_game
    {:ok, game} = Games.create_game(%{scenario_id: scenario.id, modular_sets: []}, actor: user)

    game
  end

  describe "index page" do
    setup %{conn: conn} do
      user = Sanctum.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      {:ok, conn: conn, user: user}
    end

    test "renders games index page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/games")

      # Just assert that the page loads without crashing
      assert html =~ "Sanctum"
    end

    test "renders games index with existing game", %{conn: conn, user: user} do
      _game = create_test_game(user)

      {:ok, view, html} = live(conn, ~p"/games")

      # The shell paints immediately; the games list loads asynchronously.
      assert html =~ "Sanctum"
      assert render_async(view) =~ "Test Villain"
    end

    test "shows new game button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/games")

      assert html =~ "New Game"
    end
  end
end
