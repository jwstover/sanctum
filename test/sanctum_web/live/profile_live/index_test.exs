defmodule SanctumWeb.ProfileLive.IndexTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "anonymous visitors are redirected to sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/profile")
  end

  describe "collection section" do
    import Sanctum.Factory

    defp core_pack do
      {:ok, wave} =
        Sanctum.Catalog.find_or_create_wave(%{number: 1, name: "Wave 1"}, authorize?: false)

      create(Sanctum.Catalog.Pack,
        action: :upsert_from_marvelcdb,
        attrs: %{code: "core", name: "Core Set"}
      )
      |> Ash.Changeset.for_update(:set_curated, %{product_type: :core, wave_id: wave.id})
      |> Ash.update!(authorize?: false)
    end

    defp checkbox(view, pack) do
      element(view, ~s{input[phx-click="toggle_pack"][phx-value-id="#{pack.id}"]})
    end

    test "lists every catalog pack with an unchecked box for a fresh user", %{conn: conn} do
      pack = core_pack()

      {:ok, view, _html} = live(log_in_user(conn, user_fixture()), ~p"/profile")
      html = render(view)

      assert html =~ "Wave 1 · 0 / 1"
      assert html =~ "0 cards owned"
      assert has_element?(view, ~s{input[phx-click="toggle_pack"][phx-value-id="#{pack.id}"]})
      refute has_element?(view, ~s{input[phx-value-id="#{pack.id}"][checked]})
    end

    test "checking and unchecking a pack updates the collection", %{conn: conn} do
      user = user_fixture()
      pack = core_pack()
      card = create(Sanctum.Games.Card, attrs: %{pack_id: pack.id})

      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/profile")

      html = view |> checkbox(pack) |> render_click()

      assert html =~ "Wave 1 · 1 / 1"
      assert html =~ "1 cards owned"
      assert Sanctum.Collections.pack_owned?(pack.id, user)
      assert Ash.get!(Sanctum.Games.Card, card.id, actor: user, load: [:owned]).owned

      html = view |> checkbox(pack) |> render_click()

      assert html =~ "Wave 1 · 0 / 1"
      assert html =~ "0 cards owned"
      refute Sanctum.Collections.pack_owned?(pack.id, user)
    end

    test "shows override counts alongside the checklist", %{conn: conn} do
      user = user_fixture()
      core_pack()
      Sanctum.Collections.set_card_status!(create(Sanctum.Games.Card).id, :owned, actor: user)

      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/profile")
      html = render(view)

      assert html =~ "1 cards owned"
      assert html =~ "1 individually added card"
    end

    test "one user's collection never shows on another's profile", %{conn: conn} do
      owner = user_fixture()
      pack = core_pack()
      Sanctum.Collections.add_pack!(pack.id, actor: owner)

      {:ok, view, _html} = live(log_in_user(conn, user_fixture()), ~p"/profile")
      html = render(view)

      assert html =~ "Wave 1 · 0 / 1"
      assert html =~ "0 cards owned"
      refute has_element?(view, ~s{input[phx-value-id="#{pack.id}"][checked]})
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
