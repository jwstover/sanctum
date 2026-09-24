defmodule Sanctum.MarvelCdb.OAuth do
  @moduledoc """
  OAuth2 authorization-code flow against MarvelCDB.

  MarvelCDB runs Symfony's FOSOAuthServerBundle, which exposes the two standard
  endpoints below and issues **no scopes** — authorization is all-or-nothing for
  a client. Credentials are hand-issued by the site admin and pinned to a fixed
  redirect URI at provisioning time, so `redirect_uri/0` must match what was
  registered exactly or the authorize step is rejected.

  This is hand-rolled rather than an `AshAuthentication` strategy on purpose:
  that DSL is built to register-or-sign-in a `User` from a `user_url` returning
  a subject claim, and MarvelCDB's OAuth API has neither a user-info endpoint
  nor an email to key on. Here the flow only ever *links* a MarvelCDB grant to
  an already-signed-in Sanctum user — see `Sanctum.Accounts.McdbCredential`.

  Tokens come back from a JSON body; unlike MarvelCDB's `/api/oauth2` deck
  endpoints (which signal failure as `success: false` in a 200 body), the token
  endpoint uses real HTTP status codes and the standard `error` /
  `error_description` shape.

  MarvelCDB's OAuth API has no user-info endpoint, so `owner_id/1` identifies
  the token owner indirectly: it lists the owner's decks (`/api/oauth2/decks`)
  and reads the `user_id` MarvelCDB stamps on each one. A user with no decks
  gives up no id at all — the endpoint 500s on an empty list rather than
  returning `[]`, which is treated as the same "no decks yet" outcome.
  """

  require Logger

  @authorize_url "https://marvelcdb.com/oauth/v2/auth"
  @token_url "https://marvelcdb.com/oauth/v2/token"
  @decks_url "https://marvelcdb.com/api/oauth2/decks"

  @doc """
  The URL to send the user to so they can authorize Sanctum.

  `state` is echoed back to the callback and must be compared against the value
  stashed in the session — it is the CSRF defense for the flow.
  """
  @spec authorize_url(String.t()) :: String.t()
  def authorize_url(state) do
    query =
      URI.encode_query(%{
        "client_id" => client_id(),
        "redirect_uri" => redirect_uri(),
        "response_type" => "code",
        "state" => state
      })

    @authorize_url <> "?" <> query
  end

  @doc """
  Exchanges an authorization code for a token pair.

  `redirect_uri` is required again here by the spec (and by the bundle) even
  though there is nothing to redirect to — it must match the authorize step.
  """
  @spec exchange_code(String.t()) :: {:ok, map()} | {:error, term()}
  def exchange_code(code) do
    post_token(%{
      "grant_type" => "authorization_code",
      "code" => code,
      "redirect_uri" => redirect_uri()
    })
  end

  @doc "Trades a refresh token for a fresh token pair."
  @spec refresh(String.t()) :: {:ok, map()} | {:error, term()}
  def refresh(refresh_token) do
    post_token(%{
      "grant_type" => "refresh_token",
      "refresh_token" => refresh_token
    })
  end

  @doc """
  Whether MarvelCDB OAuth is configured at all.

  Both halves of the client credential must be present; without them the
  connect flow is hidden rather than failing at the redirect.
  """
  @spec configured?() :: boolean()
  def configured?, do: present?(client_id()) and present?(client_secret())

  def client_id, do: Application.get_env(:sanctum, :marvelcdb_client_id)
  def client_secret, do: Application.get_env(:sanctum, :marvelcdb_client_secret)
  def redirect_uri, do: Application.get_env(:sanctum, :marvelcdb_redirect_uri)

  @doc """
  Lists the decks owned by the token holder, straight from MarvelCDB's
  `/api/oauth2/decks` endpoint.

  A status of 500+ is treated as expected rather than a failure — it's what
  the endpoint does for an account with zero decks (`max([])` blows up
  server-side) as much as for a real outage, and callers can't tell those
  apart from here.
  """
  @spec list_decks(String.t()) :: {:ok, list(map())} | {:error, term()}
  def list_decks(access_token) do
    started_at = System.monotonic_time(:millisecond)
    result = Req.get(@decks_url, [auth: {:bearer, access_token}] ++ req_options())

    :telemetry.execute(
      [:sanctum, :marvel_cdb, :request, :stop],
      %{duration_ms: System.monotonic_time(:millisecond) - started_at},
      %{endpoint: "oauth2/decks", status: status_tag(result)}
    )

    handle_decks_response(result)
  end

  @doc """
  Resolves the MarvelCDB account id behind an access token from the `user_id`
  on the owner's own decks — the OAuth API exposes no user-info endpoint, so
  this is the only signal available. `{:error, :no_decks}` covers both a
  deckless account and MarvelCDB's 500-on-empty quirk; there's no way to tell
  them apart from the response alone.
  """
  @spec owner_id(String.t()) :: {:ok, integer()} | {:error, term()}
  def owner_id(access_token) do
    case list_decks(access_token) do
      {:ok, decks} ->
        decks
        |> Enum.map(& &1["user_id"])
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> case do
          [id] -> {:ok, id}
          [] -> {:error, :no_decks}
          _ids -> {:error, :ambiguous_owner}
        end

      {:error, {:server_error, status}} ->
        Logger.warning("MarvelCDB decks lookup got a server error (status #{status})")
        {:error, :no_decks}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_decks_response({:ok, %Req.Response{status: 200, body: body}})
       when is_list(body) do
    {:ok, body}
  end

  defp handle_decks_response({:ok, %Req.Response{status: 200}}) do
    Logger.warning("MarvelCDB decks response was 200 but not a list")
    {:error, :unexpected_response}
  end

  defp handle_decks_response({:ok, %Req.Response{status: status}}) when status >= 500 do
    {:error, {:server_error, status}}
  end

  defp handle_decks_response({:ok, %Req.Response{status: status}}) do
    Logger.warning("MarvelCDB decks lookup failed (status #{status})")
    {:error, {:http_error, status}}
  end

  defp handle_decks_response({:error, reason}) do
    Logger.warning("MarvelCDB decks lookup transport error: #{inspect(reason)}")
    {:error, {:transport_error, reason}}
  end

  defp post_token(params) do
    params =
      Map.merge(params, %{
        "client_id" => client_id(),
        "client_secret" => client_secret()
      })

    started_at = System.monotonic_time(:millisecond)
    result = Req.post(@token_url, [form: params] ++ req_options())

    :telemetry.execute(
      [:sanctum, :marvel_cdb, :request, :stop],
      %{duration_ms: System.monotonic_time(:millisecond) - started_at},
      %{endpoint: "oauth/token", status: status_tag(result)}
    )

    handle_token_response(result)
  end

  defp handle_token_response({:ok, %Req.Response{status: 200, body: body}})
       when is_map(body) do
    case body do
      %{"access_token" => access_token} when is_binary(access_token) ->
        {:ok,
         %{
           access_token: access_token,
           refresh_token: body["refresh_token"],
           expires_at: expires_at(body["expires_in"])
         }}

      _ ->
        Logger.warning("MarvelCDB token response missing access_token")
        {:error, :invalid_token_response}
    end
  end

  # The bundle answers a bad/expired code or a redirect_uri mismatch with a 4xx
  # and an OAuth2 error body. Surface the code so callers can tell a dead
  # refresh token (`invalid_grant` — reconnect) from a misconfiguration.
  defp handle_token_response({:ok, %Req.Response{status: status, body: body}}) do
    error = if is_map(body), do: body["error"], else: nil
    description = if is_map(body), do: body["error_description"], else: nil

    Logger.warning(
      "MarvelCDB token exchange failed (status #{status}): #{inspect(error)} #{inspect(description)}"
    )

    {:error, {:oauth_error, error || :unknown, status}}
  end

  defp handle_token_response({:error, reason}) do
    Logger.warning("MarvelCDB token exchange transport error: #{inspect(reason)}")
    {:error, {:transport_error, reason}}
  end

  # A token with no stated lifetime is treated as already expired rather than
  # eternally valid, so the first use refreshes instead of sending a dead token.
  defp expires_at(expires_in) when is_integer(expires_in) do
    DateTime.add(DateTime.utc_now(), expires_in, :second)
  end

  defp expires_at(_), do: DateTime.utc_now()

  defp status_tag({:ok, %Req.Response{status: status}}), do: status
  defp status_tag({:error, _}), do: :error

  defp present?(value), do: is_binary(value) and value != ""

  # Same test seam as `Sanctum.MarvelCdb` — lets the suite stub the HTTP layer.
  defp req_options, do: Application.get_env(:sanctum, :marvel_cdb_req_options, [])
end
