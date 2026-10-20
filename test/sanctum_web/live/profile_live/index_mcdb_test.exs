defmodule SanctumWeb.ProfileLive.IndexMcdbTest do
  @moduledoc false

  # async: false — these toggle the global MarvelCDB client-id env.
  use SanctumWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Sanctum.Decks
  alias Sanctum.MarvelCdb.Credentials

  setup do
    original_id = Application.get_env(:sanctum, :marvelcdb_client_id)
    original_secret = Application.get_env(:sanctum, :marvelcdb_client_secret)

    on_exit(fn ->
      Application.put_env(:sanctum, :marvelcdb_client_id, original_id)
      Application.put_env(:sanctum, :marvelcdb_client_secret, original_secret)
    end)

    :ok
  end

  defp configure! do
    Application.put_env(:sanctum, :marvelcdb_client_id, "test-client-id")
    Application.put_env(:sanctum, :marvelcdb_client_secret, "test-client-secret")
  end

  defp unconfigure! do
    Application.put_env(:sanctum, :marvelcdb_client_id, nil)
    Application.put_env(:sanctum, :marvelcdb_client_secret, nil)
  end

  test "no MarvelCDB panel when unconfigured and never connected", %{conn: conn} do
    unconfigure!()

    {:ok, view, _html} = live(log_in_user(conn, user_fixture()), ~p"/profile")

    refute has_element?(view, ~s{a[href="/marvelcdb/connect"]})
    refute has_element?(view, "h2", "MarvelCDB")
  end

  test "a configured server offers a connect link", %{conn: conn} do
    configure!()

    {:ok, view, html} = live(log_in_user(conn, user_fixture()), ~p"/profile")

    assert html =~ "MarvelCDB"
    assert has_element?(view, ~s{a[href="/marvelcdb/connect"]}, "Connect MarvelCDB")
  end

  test "a linked account shows its username", %{conn: conn} do
    configure!()
    user = user_fixture()

    {:ok, _} =
      Credentials.connect(user, %{
        access_token: "access-abc",
        refresh_token: "refresh-xyz",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

    {:ok, mcdb_user} = Decks.find_or_create_mcdb_user(%{mcdb_user_id: 4242, username: "atom"})
    {:ok, _} = Decks.claim_mcdb_user(mcdb_user, actor: user)

    {:ok, _view, html} = live(log_in_user(conn, user), ~p"/profile")

    assert html =~ "@atom"
    assert html =~ "Connected"
  end

  test "a linked account with no username shows the mcdb id", %{conn: conn} do
    configure!()
    user = user_fixture()

    {:ok, _} =
      Credentials.connect(user, %{
        access_token: "access-abc",
        refresh_token: "refresh-xyz",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

    {:ok, mcdb_user} = Decks.find_or_create_mcdb_user(%{mcdb_user_id: 4242})
    {:ok, _} = Decks.claim_mcdb_user(mcdb_user, actor: user)

    {:ok, _view, html} = live(log_in_user(conn, user), ~p"/profile")

    assert html =~ "mcdb #4242"
  end

  test "connected but unlinked shows the notice and a reconnect link", %{conn: conn} do
    configure!()
    user = user_fixture()

    {:ok, _} =
      Credentials.connect(user, %{
        access_token: "access-abc",
        refresh_token: "refresh-xyz",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

    {:ok, view, html} = live(log_in_user(conn, user), ~p"/profile")

    assert html =~ "not linked to a MarvelCDB account yet"
    assert has_element?(view, ~s{a[href="/marvelcdb/connect"]}, "Reconnect")
  end

  test "disconnect_mcdb drops the credential", %{conn: conn} do
    configure!()
    user = user_fixture()

    {:ok, _} =
      Credentials.connect(user, %{
        access_token: "access-abc",
        refresh_token: "refresh-xyz",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/profile")

    html = render_click(view, "disconnect_mcdb", %{})

    refute Credentials.connected?(user)
    assert has_element?(view, ~s{a[href="/marvelcdb/connect"]}, "Connect MarvelCDB")
    refute html =~ "Connected"
  end
end
