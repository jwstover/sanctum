defmodule Sanctum.MarvelCdb.OAuthTest do
  @moduledoc false

  # async: false — these toggle the global `:marvel_cdb_req_options` env and the
  # MarvelCDB client credentials.
  use Sanctum.DataCase, async: false

  import Sanctum.AccountsFixtures

  alias Sanctum.MarvelCdb.Credentials
  alias Sanctum.MarvelCdb.OAuth

  setup do
    original_req = Application.get_env(:sanctum, :marvel_cdb_req_options)
    original_id = Application.get_env(:sanctum, :marvelcdb_client_id)
    original_secret = Application.get_env(:sanctum, :marvelcdb_client_secret)
    original_uri = Application.get_env(:sanctum, :marvelcdb_redirect_uri)

    Application.put_env(:sanctum, :marvel_cdb_req_options,
      plug: {Req.Test, Sanctum.MarvelCdb},
      retry: false
    )

    Application.put_env(:sanctum, :marvelcdb_client_id, "test-client-id")
    Application.put_env(:sanctum, :marvelcdb_client_secret, "test-client-secret")

    Application.put_env(
      :sanctum,
      :marvelcdb_redirect_uri,
      "http://localhost:4150/marvelcdb/callback"
    )

    on_exit(fn ->
      Application.put_env(:sanctum, :marvel_cdb_req_options, original_req)
      Application.put_env(:sanctum, :marvelcdb_client_id, original_id)
      Application.put_env(:sanctum, :marvelcdb_client_secret, original_secret)
      Application.put_env(:sanctum, :marvelcdb_redirect_uri, original_uri)
    end)

    :ok
  end

  # Answers the token endpoint with `body` under `status`.
  defp stub_token(body, status \\ 200) do
    Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
      conn |> Plug.Conn.put_status(status) |> Req.Test.json(body)
    end)
  end

  describe "authorize_url/1" do
    test "targets MarvelCDB's authorize endpoint with the configured client" do
      %URI{query: query} = uri = URI.parse(OAuth.authorize_url("state-123"))

      assert uri.host == "marvelcdb.com"
      assert uri.path == "/oauth/v2/auth"

      params = URI.decode_query(query)
      assert params["client_id"] == "test-client-id"
      assert params["response_type"] == "code"
      assert params["state"] == "state-123"
      assert params["redirect_uri"] == "http://localhost:4150/marvelcdb/callback"
    end

    test "never leaks the client secret into the browser-visible URL" do
      refute OAuth.authorize_url("state-123") =~ "test-client-secret"
    end
  end

  describe "exchange_code/1" do
    test "returns the token pair with expiry resolved to an absolute time" do
      stub_token(%{
        "access_token" => "access-abc",
        "refresh_token" => "refresh-xyz",
        "expires_in" => 3600
      })

      assert {:ok, token} = OAuth.exchange_code("the-code")
      assert token.access_token == "access-abc"
      assert token.refresh_token == "refresh-xyz"

      # ~1h out, with slack for test execution time.
      assert_in_delta DateTime.diff(token.expires_at, DateTime.utc_now()), 3600, 30
    end

    test "sends the grant, code, and client credentials as form params" do
      Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)

        assert params["grant_type"] == "authorization_code"
        assert params["code"] == "the-code"
        assert params["client_id"] == "test-client-id"
        assert params["client_secret"] == "test-client-secret"
        # Required again at exchange time and must match the authorize step.
        assert params["redirect_uri"] == "http://localhost:4150/marvelcdb/callback"

        Req.Test.json(conn, %{"access_token" => "a", "expires_in" => 60})
      end)

      assert {:ok, _token} = OAuth.exchange_code("the-code")
    end

    test "surfaces the OAuth error code on rejection" do
      stub_token(%{"error" => "invalid_grant", "error_description" => "Code expired"}, 400)

      assert {:error, {:oauth_error, "invalid_grant", 400}} = OAuth.exchange_code("stale")
    end

    test "treats a 200 with no access_token as invalid" do
      stub_token(%{"something" => "else"})

      assert {:error, :invalid_token_response} = OAuth.exchange_code("the-code")
    end

    test "reports transport failures separately from OAuth rejections" do
      Req.Test.stub(Sanctum.MarvelCdb, &Req.Test.transport_error(&1, :timeout))

      assert {:error, {:transport_error, _}} = OAuth.exchange_code("the-code")
    end

    # A token with no stated lifetime must not be treated as eternally valid.
    test "a response without expires_in is already expired" do
      stub_token(%{"access_token" => "access-abc"})

      assert {:ok, token} = OAuth.exchange_code("the-code")
      assert DateTime.compare(token.expires_at, DateTime.utc_now()) != :gt
    end
  end

  describe "configured?/0" do
    test "is false when either half of the credential is missing" do
      Application.put_env(:sanctum, :marvelcdb_client_secret, nil)
      refute OAuth.configured?()

      Application.put_env(:sanctum, :marvelcdb_client_secret, "")
      refute OAuth.configured?()

      Application.put_env(:sanctum, :marvelcdb_client_secret, "test-client-secret")
      assert OAuth.configured?()
    end
  end

  describe "credential storage" do
    setup do
      %{user: user_fixture()}
    end

    test "connect then fetch returns the stored access token", %{user: user} do
      token = %{
        access_token: "access-abc",
        refresh_token: "refresh-xyz",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      assert {:ok, _credential} = Credentials.connect(user, token)
      assert Credentials.connected?(user)
      assert {:ok, "access-abc"} = Credentials.fetch_access_token(user)
    end

    test "reconnecting replaces the grant rather than accumulating", %{user: user} do
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, _} =
        Credentials.connect(user, %{
          access_token: "first",
          refresh_token: "r1",
          expires_at: expires_at
        })

      {:ok, _} =
        Credentials.connect(user, %{
          access_token: "second",
          refresh_token: "r2",
          expires_at: expires_at
        })

      assert {:ok, "second"} = Credentials.fetch_access_token(user)

      credentials =
        Sanctum.Accounts.McdbCredential |> Ash.read!(authorize?: false)

      assert length(credentials) == 1
    end

    test "an unconnected user has no token", %{user: user} do
      refute Credentials.connected?(user)
      assert {:error, :not_connected} = Credentials.fetch_access_token(user)
    end

    test "one user's credential is invisible to another", %{user: user} do
      other = user_fixture()

      {:ok, _} =
        Credentials.connect(user, %{
          access_token: "access-abc",
          refresh_token: "refresh-xyz",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      refute Credentials.connected?(other)
      assert {:error, :not_connected} = Credentials.fetch_access_token(other)
    end

    test "tokens are encrypted at rest", %{user: user} do
      {:ok, _} =
        Credentials.connect(user, %{
          access_token: "super-secret-token",
          refresh_token: "refresh-xyz",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      %{rows: [[stored]]} =
        Sanctum.Repo.query!("SELECT encrypted_access_token FROM mcdb_credentials LIMIT 1")

      refute stored =~ "super-secret-token"
    end

    test "disconnect drops the grant and is safe to repeat", %{user: user} do
      {:ok, _} =
        Credentials.connect(user, %{
          access_token: "access-abc",
          refresh_token: "refresh-xyz",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert :ok = Credentials.disconnect(user)
      refute Credentials.connected?(user)
      assert :ok = Credentials.disconnect(user)
    end
  end

  describe "refresh on expiry" do
    setup do
      %{user: user_fixture()}
    end

    defp connect_expired(user, refresh_token) do
      Credentials.connect(user, %{
        access_token: "stale-access",
        refresh_token: refresh_token,
        expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
      })
    end

    test "an expired token is refreshed and the new pair persisted", %{user: user} do
      {:ok, _} = connect_expired(user, "refresh-xyz")

      stub_token(%{
        "access_token" => "fresh-access",
        "refresh_token" => "rotated-refresh",
        "expires_in" => 3600
      })

      assert {:ok, "fresh-access"} = Credentials.fetch_access_token(user)

      # The rotated pair is stored, so the next call needs no refresh — stub a
      # failure to prove the network isn't touched again.
      Req.Test.stub(Sanctum.MarvelCdb, &Req.Test.transport_error(&1, :timeout))
      assert {:ok, "fresh-access"} = Credentials.fetch_access_token(user)
    end

    test "a token expiring within the safety margin refreshes early", %{user: user} do
      {:ok, _} =
        Credentials.connect(user, %{
          access_token: "about-to-die",
          refresh_token: "refresh-xyz",
          expires_at: DateTime.add(DateTime.utc_now(), 10, :second)
        })

      stub_token(%{"access_token" => "fresh-access", "expires_in" => 3600})

      assert {:ok, "fresh-access"} = Credentials.fetch_access_token(user)
    end

    test "a refresh response without a new refresh token keeps the old one", %{user: user} do
      {:ok, _} = connect_expired(user, "keep-me")

      stub_token(%{"access_token" => "fresh-access", "expires_in" => 3600})
      assert {:ok, "fresh-access"} = Credentials.fetch_access_token(user)

      credential =
        Sanctum.Accounts.McdbCredential
        |> Ash.read_one!(authorize?: false)
        |> Ash.load!([:refresh_token], authorize?: false)

      assert credential.refresh_token == "keep-me"
    end

    test "an expired grant with no refresh token demands reauthorization", %{user: user} do
      {:ok, _} = connect_expired(user, nil)

      assert {:error, :reauthorization_required} = Credentials.fetch_access_token(user)
    end

    test "a refresh token MarvelCDB refuses demands reauthorization", %{user: user} do
      {:ok, _} = connect_expired(user, "revoked")

      stub_token(%{"error" => "invalid_grant"}, 400)

      assert {:error, :reauthorization_required} = Credentials.fetch_access_token(user)
    end

    # A blip talking to MarvelCDB is transient — it must not read as a revoked
    # grant, or a network hiccup would push users through a needless reconnect.
    test "a transport failure during refresh is not mistaken for revocation", %{user: user} do
      {:ok, _} = connect_expired(user, "refresh-xyz")

      Req.Test.stub(Sanctum.MarvelCdb, &Req.Test.transport_error(&1, :timeout))

      assert {:error, {:transport_error, _}} = Credentials.fetch_access_token(user)
    end
  end
end
