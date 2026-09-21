defmodule SanctumWeb.GameLogLiveTest do
  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "index shows the empty state", %{conn: conn} do
    user =
      Sanctum.Accounts.User
      |> Ash.Changeset.for_create(:create, %{
        email: "gl#{:rand.uniform(1_000_000)}@example.com",
        confirmed_at: DateTime.utc_now()
      })
      |> Ash.create!(authorize?: false)

    conn = log_in_user(conn, user)
    {:ok, _lv, html} = live(conn, ~p"/game-log")
    assert html =~ "No games logged yet"
  end

  test "new form logs a game and redirects to it", %{conn: conn} do
    user =
      Sanctum.Accounts.User
      |> Ash.Changeset.for_create(:create, %{
        email: "gl#{:rand.uniform(1_000_000)}@example.com",
        confirmed_at: DateTime.utc_now()
      })
      |> Ash.create!(authorize?: false)

    set = "gl_scenario_#{:rand.uniform(1_000_000)}"

    {:ok, scenario} =
      Sanctum.Games.create_scenario(
        %{name: "GL Scenario", villain_set_id: Sanctum.Factory.villain_set!(set).id},
        authorize?: false
      )

    mk_card = fn attrs ->
      code = "glc#{:rand.uniform(1_000_000)}"

      card =
        Sanctum.Games.Card
        |> Ash.Changeset.for_create(:create, %{base_code: code, code: code, set: set, pack: set})
        |> Ash.create!(authorize?: false)

      Sanctum.Games.CardSide
      |> Ash.Changeset.for_create(
        :create,
        Map.merge(
          %{card_id: card.id, code: code, side_identifier: "A", is_primary_side: true},
          attrs
        )
      )
      |> Ash.create!(authorize?: false)

      card
    end

    mk_card.(%{name: "GL Villain", type: :villain, health: %{value: 10}})
    mk_card.(%{name: "GL Scheme", type: :main_scheme})
    hero_card = mk_card.(%{name: "GL Hero", type: :hero})

    hero =
      Sanctum.Heroes.create_hero!(
        %{hero_name: "GL Hero", set: "gl_hero", card_id: hero_card.id},
        authorize?: false
      )

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/game-log/new")

    html =
      lv
      |> form("#game-log-form", %{
        "scenario_id" => scenario.id,
        "players" => %{"0" => %{"hero_id" => hero.id, "aspect" => "justice"}}
      })
      |> render_change()

    assert html =~ "GL Villain"
    refute html =~ "Which main scheme was used?"

    lv |> form("#game-log-form") |> render_submit()
    {path, _flash} = assert_redirect(lv)
    assert path =~ "/game-log/"

    {:ok, _lv, html} = live(log_in_user(conn, user), path)
    assert html =~ "GL Hero"
    assert html =~ "Justice"
  end
end
