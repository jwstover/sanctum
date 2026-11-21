defmodule SanctumWeb.ScenarioLive.ShowActionsTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.AccountsFixtures
  import Sanctum.Factory

  setup do
    villain_set = villain_set!()

    modular =
      Sanctum.Catalog.CardSet
      |> Ash.Changeset.for_create(:upsert, %{
        code: "zz_menu_modular",
        name: "Zz Menu Modular",
        set_type: :modular
      })
      |> Ash.create!(authorize?: false)

    owner = user_fixture()

    official =
      Sanctum.Games.create_scenario!(
        %{
          name: "Zz Official",
          description_md: "Official notes",
          villain_set_id: villain_set.id,
          modular_sets: [modular.id]
        },
        authorize?: false
      )

    mine =
      Sanctum.Games.build_scenario!(%{name: "Zz Mine", villain_set_id: villain_set.id},
        actor: owner
      )

    %{modular: modular, owner: owner, official: official, mine: mine}
  end

  defp show(conn, scenario) do
    {:ok, view, _} = live(conn, ~p"/scenarios/#{scenario.id}")
    render_async(view)
    view
  end

  describe "menu items" do
    test "signed out: copy link only", ctx do
      view = show(ctx.conn, ctx.mine)

      assert has_element?(view, ~s(#scenario-menu-trigger[aria-label="More actions"]))
      assert has_element?(view, "#scenario-menu-trigger[aria-expanded=false]")

      assert has_element?(
               view,
               ~s(#scenario-copy-link[data-url="http://localhost:4002/scenarios/#{ctx.mine.id}"])
             )

      refute has_element?(view, "#scenario-duplicate")
      refute has_element?(view, "#scenario-delete")
      refute has_element?(view, "#scenario-delete-confirm")
    end

    test "signed in, not the owner: copy link and duplicate", ctx do
      view = show(log_in_user(ctx.conn, user_fixture()), ctx.mine)

      assert has_element?(view, "#scenario-copy-link")
      assert has_element?(view, "#scenario-duplicate")
      refute has_element?(view, "#scenario-delete")
    end

    test "owner: every item", ctx do
      view = show(log_in_user(ctx.conn, ctx.owner), ctx.mine)

      assert has_element?(view, "#scenario-copy-link")
      assert has_element?(view, "#scenario-duplicate")
      assert has_element?(view, "#scenario-delete", "Delete scenario")
      assert has_element?(view, "#scenario-delete-confirm")
    end

    test "admin: every item, even on an official scenario", ctx do
      view = show(log_in_user(ctx.conn, admin_user_fixture()), ctx.official)

      assert has_element?(view, "#scenario-duplicate")
      assert has_element?(view, "#scenario-delete")
    end
  end

  test "duplicate copies an official scenario and opens the copy's build page", ctx do
    user = user_fixture()
    view = show(log_in_user(ctx.conn, user), ctx.official)

    assert {:error, {:live_redirect, %{to: "/scenarios/" <> rest}}} =
             view |> element("#scenario-duplicate") |> render_click()

    [id, "build"] = String.split(rest, "/")
    copy = Sanctum.Games.get_scenario!(id, load: [:modular_sets])

    assert copy.name == "Copy of Zz Official"
    assert copy.owner_id == user.id
    assert copy.description_md == "Official notes"
    assert Enum.map(copy.modular_sets, & &1.id) == [ctx.modular.id]
  end

  test "delete removes the scenario and returns to the browser", ctx do
    conn = log_in_user(ctx.conn, ctx.owner)
    view = show(conn, ctx.mine)

    assert {:ok, _index, html} =
             view
             |> element("#scenario-delete-confirm [data-confirm-ok]")
             |> render_click()
             |> follow_redirect(conn, ~p"/scenarios")

    assert html =~ "Scenario deleted."
    assert {:error, _} = Sanctum.Games.get_scenario(ctx.mine.id)
  end

  test "delete is blocked while a logged game references the scenario", ctx do
    villain = Sanctum.Villains.find_or_create_villain!(%{villain_name: "Zz V", set: ctx.mine.set})

    Ash.Seed.seed!(Sanctum.GameLog.LoggedGame, %{
      user_id: user_fixture().id,
      scenario_id: ctx.mine.id,
      villain_id: villain.id
    })

    view = show(log_in_user(ctx.conn, ctx.owner), ctx.mine)
    html = view |> element("#scenario-delete-confirm [data-confirm-ok]") |> render_click()

    assert html =~ "This scenario has 1 logged game, so it can&#39;t be deleted."
    assert {:ok, _} = Sanctum.Games.get_scenario(ctx.mine.id)
  end
end
