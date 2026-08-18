defmodule SanctumWeb.MarvelCdbAuthController do
  @moduledoc """
  Links a signed-in Sanctum user's account to their MarvelCDB account over
  OAuth2, so Sanctum can publish decks back to the site on their behalf.

  This is account *linking*, not sign-in: the user must already be signed in to
  Sanctum, and nothing here creates or authenticates a `User`. See
  `Sanctum.MarvelCdb.OAuth` for why it doesn't go through AshAuthentication.
  """

  use SanctumWeb, :controller

  require Logger

  alias Sanctum.MarvelCdb.Credentials
  alias Sanctum.MarvelCdb.OAuth

  @state_session_key :marvel_cdb_oauth_state

  @doc "Kicks off the flow: stash a CSRF state and bounce to MarvelCDB."
  def authorize(conn, _params) do
    with {:ok, conn} <- require_user(conn),
         {:ok, conn} <- require_configured(conn) do
      state = generate_state()

      conn
      |> put_session(@state_session_key, state)
      |> redirect(external: OAuth.authorize_url(state))
    end
  end

  @doc """
  Handles MarvelCDB's redirect back.

  The `state` check runs before the code is spent: a callback that doesn't match
  the session is a forged request, and exchanging its code would bind an
  attacker's MarvelCDB account to this user.
  """
  def callback(conn, %{"code" => code, "state" => state}) do
    with {:ok, conn} <- require_user(conn),
         {:ok, conn} <- verify_state(conn, state) do
      exchange_and_store(conn, code)
    end
  end

  # The user declined on MarvelCDB's consent screen (or the server rejected the
  # request outright) — not an error worth alarming them about.
  def callback(conn, %{"error" => _} = params) do
    conn
    |> clear_state()
    |> put_flash(:info, denial_message(params))
    |> redirect(to: ~p"/profile")
  end

  def callback(conn, _params) do
    conn
    |> clear_state()
    |> put_flash(:error, "MarvelCDB sent back an unexpected response. Please try again.")
    |> redirect(to: ~p"/profile")
  end

  @doc "Forgets the stored grant. Does not revoke it on MarvelCDB's side."
  def disconnect(conn, _params) do
    with {:ok, conn} <- require_user(conn) do
      case Credentials.disconnect(conn.assigns.current_user) do
        :ok ->
          conn
          |> put_flash(:info, "Disconnected from MarvelCDB.")
          |> redirect(to: ~p"/profile")

        {:error, _reason} ->
          conn
          |> put_flash(:error, "Could not disconnect from MarvelCDB. Please try again.")
          |> redirect(to: ~p"/profile")
      end
    end
  end

  defp exchange_and_store(conn, code) do
    user = conn.assigns.current_user

    with {:ok, token} <- OAuth.exchange_code(code),
         {:ok, _credential} <- Credentials.connect(user, token) do
      conn
      |> clear_state()
      |> put_flash(:info, "Your MarvelCDB account is connected.")
      |> redirect(to: ~p"/profile")
    else
      {:error, reason} ->
        Logger.warning("MarvelCDB account linking failed: #{inspect(reason)}")

        conn
        |> clear_state()
        |> put_flash(:error, "Could not connect your MarvelCDB account. Please try again.")
        |> redirect(to: ~p"/profile")
    end
  end

  defp require_user(%{assigns: %{current_user: %{} = _user}} = conn), do: {:ok, conn}

  defp require_user(conn) do
    conn
    |> put_flash(:error, "Sign in to connect your MarvelCDB account.")
    |> redirect(to: ~p"/sign-in")
  end

  defp require_configured(conn) do
    if OAuth.configured?() do
      {:ok, conn}
    else
      conn
      |> put_flash(:error, "MarvelCDB integration isn't configured on this server.")
      |> redirect(to: ~p"/profile")
    end
  end

  # Single-use: the state is dropped whether or not it matched, so a replayed
  # callback can't ride the same session value twice.
  defp verify_state(conn, state) do
    expected = get_session(conn, @state_session_key)
    conn = clear_state(conn)

    if is_binary(expected) and Plug.Crypto.secure_compare(expected, state) do
      {:ok, conn}
    else
      conn
      |> put_flash(:error, "That MarvelCDB sign-in expired. Please try again.")
      |> redirect(to: ~p"/profile")
    end
  end

  defp denial_message(%{"error" => "access_denied"}),
    do: "MarvelCDB connection cancelled."

  defp denial_message(_params),
    do: "MarvelCDB declined the connection. Please try again."

  defp clear_state(conn), do: delete_session(conn, @state_session_key)

  defp generate_state, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
