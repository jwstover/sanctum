defmodule SanctumWeb.ProfileLive.IndexTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "anonymous visitors are redirected to sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/profile")
  end

  describe "collection section" do
    import Sanctum.Factory

    # Wave 60 / "prof_core" sit outside the wave-1..10/"core" namespace the
    # async sync tests upsert — colliding unique keys across sandboxed
    # transactions deadlock.
    defp core_pack do
      {:ok, wave} =
        Sanctum.Catalog.find_or_create_wave(%{number: 60, name: "Wave 60"}, authorize?: false)

      create(Sanctum.Catalog.Pack,
        action: :upsert_from_marvelcdb,
        attrs: %{code: "prof_core", name: "Core Set"}
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

      assert html =~ "Wave 60 · 0 / 1"
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

      assert html =~ "Wave 60 · 1 / 1"
      assert html =~ "1 cards owned"
      assert Sanctum.Collections.pack_owned?(pack.id, user)
      assert Ash.get!(Sanctum.Games.Card, card.id, actor: user, load: [:owned]).owned

      html = view |> checkbox(pack) |> render_click()

      assert html =~ "Wave 60 · 0 / 1"
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

      assert html =~ "Wave 60 · 0 / 1"
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

  describe "AI card extraction (BYOK)" do
    import Sanctum.AccountsFixtures

    alias Sanctum.Accounts

    defp stub_key_check(status, body) do
      Req.Test.stub(Sanctum.CardVision, fn conn ->
        conn
        |> Plug.Conn.put_status(status)
        |> Req.Test.json(body)
      end)
    end

    test "shows the add-key form and no connected state for a fresh user", %{conn: conn} do
      {:ok, view, _html} = live(log_in_user(conn, user_fixture()), ~p"/profile")

      assert has_element?(view, "#api-key-form input[name='api_key[key]']")
      refute render(view) =~ "Connected"
    end

    test "a valid key validates, stores encrypted, and shows the masked hint", %{conn: conn} do
      user = user_fixture()
      stub_key_check(200, %{"data" => []})

      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/profile")

      view
      |> form("#api-key-form", %{"api_key" => %{"key" => "sk-ant-secret-VALUE9zX"}})
      |> render_submit()

      html = render_async(view)
      assert html =~ "validated and saved"
      assert html =~ "Connected"
      assert html =~ "sk-…E9zX"

      # Stored, encrypted, decryptable only with the actor.
      assert {:ok, row} = Accounts.api_key_for_provider(:anthropic, actor: user)
      assert row.key_hint == "E9zX"
      assert Ash.load!(row, [:key], actor: user).key == "sk-ant-secret-VALUE9zX"
    end

    test "a rejected key surfaces an error and stores nothing", %{conn: conn} do
      user = user_fixture()
      stub_key_check(401, %{"error" => %{"message" => "invalid x-api-key"}})

      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/profile")

      view
      |> form("#api-key-form", %{"api_key" => %{"key" => "sk-ant-bogus"}})
      |> render_submit()

      html = render_async(view)
      assert html =~ "Anthropic rejected that key"
      assert {:ok, nil} = Accounts.api_key_for_provider(:anthropic, actor: user)
    end

    test "removing a stored key clears it", %{conn: conn} do
      user = user_fixture()

      Accounts.upsert_api_key!(
        %{provider: :anthropic, key: "sk-ant-secret-VALUE9zX", key_hint: "E9zX"},
        actor: user
      )

      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/profile")
      assert render(view) =~ "Connected"

      view
      |> element("#confirm-remove-api-key button[phx-click='remove_api_key']")
      |> render_click()

      html = render(view)
      assert html =~ "Anthropic key removed"
      refute html =~ "Connected"
      assert {:ok, nil} = Accounts.api_key_for_provider(:anthropic, actor: user)
    end
  end
end
