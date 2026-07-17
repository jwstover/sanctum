defmodule SanctumWeb.ProfileLive.IndexTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "anonymous visitors are redirected to sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/profile")
  end

  test "a signed-in user can claim a username", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, view, html} = live(conn, ~p"/profile")
    assert html =~ "Save username"

    html =
      view
      |> form("#profile-form", %{profile: %{username: "web_head"}})
      |> render_submit()

    assert html =~ "@web_head"
    assert html =~ "Username saved."

    reloaded = Ash.get!(Sanctum.Accounts.User, user.id, authorize?: false)
    assert to_string(reloaded.username) == "web_head"
  end

  test "an invalid username shows an error", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/profile")

    html =
      view
      |> form("#profile-form", %{profile: %{username: "no spaces allowed"}})
      |> render_submit()

    assert html =~ "letters, numbers, and underscores only"

    reloaded = Ash.get!(Sanctum.Accounts.User, user.id, authorize?: false)
    assert reloaded.username == nil
  end

  test "a taken username shows an error", %{conn: conn} do
    user_fixture(username: "taken_name")
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/profile")

    html =
      view
      |> form("#profile-form", %{profile: %{username: "taken_name"}})
      |> render_submit()

    assert html =~ "has already been taken"
  end

  describe "claim-username banner" do
    test "shows for signed-in users without a username", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/decks")

      assert has_element?(view, "#update-profile-banner")
    end

    test "absent once a username is claimed", %{conn: conn} do
      user = user_fixture(username: "already_set")
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/decks")

      refute has_element?(view, "#update-profile-banner")
    end

    test "absent for anonymous visitors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/decks")

      refute has_element?(view, "#update-profile-banner")
    end
  end
end
