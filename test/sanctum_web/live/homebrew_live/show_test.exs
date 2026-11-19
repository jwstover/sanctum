defmodule SanctumWeb.HomebrewLive.ShowTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.AccountsFixtures

  alias Sanctum.Homebrew

  defp project_fixture(actor) do
    Homebrew.create_project!(%{name: "Test Pack", attestation: true}, actor: actor)
  end

  defp set_fixture(project, actor, name) do
    Homebrew.create_set!(%{homebrew_project_id: project.id, name: name}, actor: actor)
  end

  # Homebrew is TEMPORARILY admin-gated at the router (see router.ex), so the
  # page tests act as an admin. Cross-user privacy semantics stay covered by
  # the data-layer tests (card_privacy_test etc.), which use plain users.
  setup %{conn: conn} do
    creator = admin_user_fixture()
    project = project_fixture(creator)
    %{conn: log_in_user(conn, creator), creator: creator, project: project}
  end

  test "anonymous visitors are redirected to sign-in", %{project: project} do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/homebrew/#{project.id}")
  end

  test "non-admins are redirected away", %{project: project} do
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(user_fixture())

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/homebrew/#{project.id}")
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/homebrew")
  end

  test "lists the project's sets with counts, linking to each set page", ctx do
    set = set_fixture(ctx.project, ctx.creator, "Kingpin Scenario")

    {:ok, _card} =
      Homebrew.create_custom_card(
        %{
          homebrew_set_id: set.id,
          card_sides: [%{image_url: "https://img.test/a.png", filename: "goon.png"}]
        },
        ctx.creator
      )

    set_fixture(ctx.project, ctx.creator, "Daredevil Hero Pack")

    {:ok, _lv, html} = live(ctx.conn, ~p"/homebrew/#{ctx.project.id}")

    assert html =~ "Kingpin Scenario"
    assert html =~ "Daredevil Hero Pack"
    assert html =~ ~p"/homebrew/#{ctx.project.id}/sets/#{set.id}"
    assert html =~ "2 sets"
    assert html =~ "1 card"
    assert html =~ "0 cards"
  end

  test "has no upload affordance", ctx do
    set_fixture(ctx.project, ctx.creator, "Kingpin")
    {:ok, lv, _html} = live(ctx.conn, ~p"/homebrew/#{ctx.project.id}")

    refute has_element?(lv, "button[phx-click='open_chooser']")
    refute has_element?(lv, "input[type='file']")
  end

  test "the inline form creates a set in this project and opens it", ctx do
    {:ok, lv, html} = live(ctx.conn, ~p"/homebrew/#{ctx.project.id}")
    assert html =~ "No sets yet"

    lv |> element("button[phx-click='start_create']") |> render_click()

    assert lv |> form("#set-form", set: %{name: ""}) |> render_change() =~ "is required"

    lv |> form("#set-form", set: %{name: "Kingpin"}) |> render_submit()

    assert [set] = Homebrew.list_project_sets!(ctx.project.id, actor: ctx.creator)
    assert set.name == "Kingpin"
    assert_redirect(lv, ~p"/homebrew/#{ctx.project.id}/sets/#{set.id}")
  end
end
