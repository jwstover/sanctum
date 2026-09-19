defmodule SanctumWeb.GameLive.NewTest do
  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.Factory

  alias Sanctum.Games

  setup %{conn: conn} do
    user = Sanctum.AccountsFixtures.user_fixture()
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  test "picker lists official and own scenarios, grouped, and hides others'", %{
    conn: conn,
    user: user
  } do
    Games.create_scenario!(%{name: "Official Rhino", villain_set_id: villain_set!().id},
      authorize?: false
    )

    Games.build_scenario!(%{name: "My Klaw", villain_set_id: villain_set!().id}, actor: user)

    Games.build_scenario!(%{name: "Their Ultron", villain_set_id: villain_set!().id},
      actor: Sanctum.AccountsFixtures.user_fixture()
    )

    {:ok, view, html} = live(conn, ~p"/games/new")

    assert html =~ "Scenario"
    assert html =~ "Official Rhino"
    assert html =~ "My Klaw"
    refute html =~ "Their Ultron"
    assert has_element?(view, ~s(optgroup[label="Official"] option), "Official Rhino")
    assert has_element?(view, ~s(optgroup[label="My scenarios"] option), "My Klaw")
  end

  test "a game created from a user-built scenario gets its villain and modular sets", %{
    conn: conn,
    user: user
  } do
    scenario =
      Games.build_scenario!(%{name: "Built", villain_set_id: villain_set!().id}, actor: user)

    modular = create(Sanctum.Catalog.CardSet, action: :upsert)
    Games.set_scenario_modular_sets!(scenario, %{modular_sets: [modular.id]}, actor: user)

    card = create(Sanctum.Games.Card, attrs: %{set: scenario.set, pack: scenario.set})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: card.id,
        code: card.code,
        type: :villain,
        name: "Built Villain",
        health: %{value: 10},
        attack: %{value: 2},
        scheme: 1
      }
    )

    {:ok, view, _html} = live(conn, ~p"/games/new")

    assert {:error, {:live_redirect, %{to: "/games/" <> game_id}}} =
             view
             |> form(~s(form[phx-submit="create"]), form: %{scenario_id: scenario.id})
             |> render_submit()

    game = Ash.get!(Games.Game, game_id, load: [:game_villain], authorize?: false)

    assert game.scenario_id == scenario.id
    assert game.modular_sets == [modular.code]
    assert game.game_villain.card_id == card.id
  end
end
