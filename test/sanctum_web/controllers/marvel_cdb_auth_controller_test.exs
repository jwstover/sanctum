defmodule SanctumWeb.MarvelCdbAuthControllerTest do
  @moduledoc false

  # async: false — these toggle the global `:marvel_cdb_req_options` env and the
  # MarvelCDB client credentials.
  use SanctumWeb.ConnCase, async: false

  alias Sanctum.MarvelCdb.Credentials

  @state_session_key :marvel_cdb_oauth_state

  setup do
    original_req = Application.get_env(:sanctum, :marvel_cdb_req_options)
    original_id = Application.get_env(:sanctum, :marvelcdb_client_id)
    original_secret = Application.get_env(:sanctum, :marvelcdb_client_secret)

    Application.put_env(:sanctum, :marvel_cdb_req_options,
      plug: {Req.Test, Sanctum.MarvelCdb},
      retry: false
    )

    Application.put_env(:sanctum, :marvelcdb_client_id, "test-client-id")
    Application.put_env(:sanctum, :marvelcdb_client_secret, "test-client-secret")

    on_exit(fn ->
      Application.put_env(:sanctum, :marvel_cdb_req_options, original_req)
      Application.put_env(:sanctum, :marvelcdb_client_id, original_id)
      Application.put_env(:sanctum, :marvelcdb_client_secret, original_secret)
    end)

    %{user: user_fixture()}
  end

  defp stub_token(body, status \\ 200) do
    Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
      conn |> Plug.Conn.put_status(status) |> Req.Test.json(body)
    end)
  end

  describe "GET /marvelcdb/connect" do
    test "redirects a signed-in user to MarvelCDB and stashes a state", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> get(~p"/marvelcdb/connect")

      location = redirected_to(conn, 302)
      assert location =~ "https://marvelcdb.com/oauth/v2/auth"

      state = get_session(conn, @state_session_key)
      assert is_binary(state) and byte_size(state) >= 32
      assert location =~ "state=#{state}"
    end

    test "sends a signed-out visitor to sign in instead", %{conn: conn} do
      conn = get(conn, ~p"/marvelcdb/connect")

      assert redirected_to(conn) == ~p"/sign-in"
      refute get_session(conn, @state_session_key)
    end

    test "refuses when the server has no MarvelCDB credentials", %{conn: conn, user: user} do
      Application.put_env(:sanctum, :marvelcdb_client_id, nil)

      conn = conn |> log_in_user(user) |> get(~p"/marvelcdb/connect")

      assert redirected_to(conn) == ~p"/profile"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "isn't configured"
    end
  end

  describe "GET /marvelcdb/callback" do
    test "stores the grant when the state matches", %{conn: conn, user: user} do
      stub_token(%{
        "access_token" => "access-abc",
        "refresh_token" => "refresh-xyz",
        "expires_in" => 3600
      })

      conn =
        conn
        |> log_in_user(user)
        |> init_test_session(%{@state_session_key => "the-state"})
        |> get(~p"/marvelcdb/callback", %{"code" => "the-code", "state" => "the-state"})

      assert redirected_to(conn) == ~p"/profile"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "connected"
      assert {:ok, "access-abc"} = Credentials.fetch_access_token(user)

      # Single-use: the state must not survive for a replay.
      refute get_session(conn, @state_session_key)
    end

    # The CSRF defense for the flow — a forged callback must never spend its
    # code, or an attacker's MarvelCDB account gets bound to this user.
    test "rejects a callback whose state doesn't match the session", %{conn: conn, user: user} do
      Req.Test.stub(Sanctum.MarvelCdb, fn _conn ->
        flunk("must not exchange a code from an unverified callback")
      end)

      conn =
        conn
        |> log_in_user(user)
        |> init_test_session(%{@state_session_key => "the-real-state"})
        |> get(~p"/marvelcdb/callback", %{"code" => "the-code", "state" => "forged"})

      assert redirected_to(conn) == ~p"/profile"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired"
      refute Credentials.connected?(user)
    end

    test "rejects a callback when the session holds no state at all", %{conn: conn, user: user} do
      Req.Test.stub(Sanctum.MarvelCdb, fn _conn ->
        flunk("must not exchange a code with no stored state")
      end)

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/marvelcdb/callback", %{"code" => "the-code", "state" => "anything"})

      assert redirected_to(conn) == ~p"/profile"
      refute Credentials.connected?(user)
    end

    test "reports a failed token exchange without connecting", %{conn: conn, user: user} do
      stub_token(%{"error" => "invalid_grant"}, 400)

      conn =
        conn
        |> log_in_user(user)
        |> init_test_session(%{@state_session_key => "the-state"})
        |> get(~p"/marvelcdb/callback", %{"code" => "stale", "state" => "the-state"})

      assert redirected_to(conn) == ~p"/profile"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Could not connect"
      refute Credentials.connected?(user)
    end

    test "handles the user declining on MarvelCDB's consent screen", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> init_test_session(%{@state_session_key => "the-state"})
        |> get(~p"/marvelcdb/callback", %{"error" => "access_denied"})

      assert redirected_to(conn) == ~p"/profile"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "cancelled"
      refute Credentials.connected?(user)
    end
  end

  describe "DELETE /marvelcdb/disconnect" do
    test "drops a connected user's grant", %{conn: conn, user: user} do
      {:ok, _} =
        Credentials.connect(user, %{
          access_token: "access-abc",
          refresh_token: "refresh-xyz",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      conn = conn |> log_in_user(user) |> delete(~p"/marvelcdb/disconnect")

      assert redirected_to(conn) == ~p"/profile"
      refute Credentials.connected?(user)
    end

    test "sends a signed-out visitor to sign in", %{conn: conn} do
      conn = delete(conn, ~p"/marvelcdb/disconnect")

      assert redirected_to(conn) == ~p"/sign-in"
    end
  end
end
