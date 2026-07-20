defmodule SanctumWeb.ProfileLive.IndexTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "anonymous visitors are redirected to sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/profile")
  end

  describe "collection section" do
    import Sanctum.Factory

    test "shows the empty state until packs are added", %{conn: conn} do
      {:ok, _view, html} = live(log_in_user(conn, user_fixture()), ~p"/profile")

      assert html =~ "Collection"
      assert html =~ "Nothing here yet"
    end

    test "lists owned packs by product type and removes them", %{conn: conn} do
      user = user_fixture()

      pack =
        create(Sanctum.Catalog.Pack,
          action: :upsert_from_marvelcdb,
          attrs: %{code: "core", name: "Core Set"}
        )
        |> Ash.Changeset.for_update(:set_curated, %{product_type: :core})
        |> Ash.update!(authorize?: false)

      card = create(Sanctum.Games.Card, attrs: %{pack_id: pack.id})
      Sanctum.Collections.add_pack!(pack.id, actor: user)
      Sanctum.Collections.set_card_status!(create(Sanctum.Games.Card).id, :owned, actor: user)

      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/profile")
      html = render(view)

      assert html =~ "Core Set"
      assert html =~ "2 cards owned"
      assert html =~ "1 individually added card"

      html = view |> element(~s{button[phx-click="remove_pack"]}) |> render_click()

      refute html =~ "Core Set"
      assert html =~ "1 cards owned"
      refute Ash.get!(Sanctum.Games.Card, card.id, actor: user, load: [:owned]).owned
    end

    test "one user's collection never shows on another's profile", %{conn: conn} do
      owner = user_fixture()

      pack =
        create(Sanctum.Catalog.Pack,
          action: :upsert_from_marvelcdb,
          attrs: %{code: "core", name: "Core Set"}
        )

      Sanctum.Collections.add_pack!(pack.id, actor: owner)

      {:ok, view, _html} = live(log_in_user(conn, user_fixture()), ~p"/profile")
      html = render(view)

      refute html =~ "Core Set"
      assert html =~ "Nothing here yet"
    end
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
