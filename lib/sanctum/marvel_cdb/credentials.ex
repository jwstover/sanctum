defmodule Sanctum.MarvelCdb.Credentials do
  @moduledoc """
  Credential lifecycle for MarvelCDB OAuth: store a grant obtained by
  `Sanctum.MarvelCdb.OAuth`, hand out a usable access token (refreshing
  transparently when it has aged out), and disconnect.

  Every call takes the `user` as the Ash actor — `Sanctum.Accounts.McdbCredential`
  filters reads and writes to the owning actor, so there is no path here that
  reaches another user's tokens.
  """

  require Logger

  alias Sanctum.Accounts
  alias Sanctum.MarvelCdb.OAuth

  # Refresh a little before the stated expiry so a token can't die in flight
  # between the check and the request that uses it.
  @expiry_margin_seconds 60

  @doc "Persists a freshly exchanged grant, replacing any existing one."
  @spec connect(struct(), map()) :: {:ok, struct()} | {:error, term()}
  def connect(user, %{access_token: _} = token) do
    Accounts.connect_marvel_cdb(
      %{
        access_token: token.access_token,
        refresh_token: token.refresh_token,
        expires_at: token.expires_at
      },
      actor: user
    )
  end

  @doc "Whether the user has a MarvelCDB grant stored (expired or not)."
  @spec connected?(struct()) :: boolean()
  def connected?(user), do: not is_nil(credential(user))

  @doc """
  Returns an access token that is valid right now, refreshing first if needed.

  `{:error, :not_connected}` means the user has never authorized (or has
  disconnected); `{:error, :reauthorization_required}` means the stored grant is
  unusable — expired with no refresh token, or refused by MarvelCDB — and the
  user has to walk the authorize flow again.
  """
  @spec fetch_access_token(struct()) :: {:ok, String.t()} | {:error, term()}
  def fetch_access_token(user) do
    case credential(user) do
      nil -> {:error, :not_connected}
      credential -> credential |> load_tokens(user) |> usable_token(user)
    end
  end

  @doc "Drops the user's stored grant. Succeeds whether or not one exists."
  @spec disconnect(struct()) :: :ok | {:error, term()}
  def disconnect(user) do
    case credential(user) do
      nil -> :ok
      credential -> Accounts.disconnect_marvel_cdb(credential, actor: user)
    end
  end

  defp credential(user) do
    case Accounts.marvel_cdb_credential(actor: user) do
      {:ok, credential} -> credential
      {:error, _} -> nil
    end
  end

  # The token columns are encrypted at rest; AshCloak exposes them as
  # calculations that have to be loaded explicitly to decrypt.
  defp load_tokens(credential, user) do
    Ash.load!(credential, [:access_token, :refresh_token], actor: user)
  end

  defp usable_token(credential, user) do
    if expired?(credential) do
      refresh(credential, user)
    else
      {:ok, credential.access_token}
    end
  end

  defp refresh(%{refresh_token: nil}, _user), do: {:error, :reauthorization_required}

  defp refresh(credential, user) do
    case OAuth.refresh(credential.refresh_token) do
      {:ok, token} ->
        rotate(credential, user, token)

      # A refused refresh token is terminal — the user revoked access on
      # MarvelCDB, or the grant aged past what the server keeps.
      {:error, {:oauth_error, _, _}} ->
        {:error, :reauthorization_required}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp rotate(credential, user, token) do
    params = %{
      access_token: token.access_token,
      # MarvelCDB rotates refresh tokens on use, but keep the old one if a
      # response omits it rather than dropping the user to a reconnect.
      refresh_token: token.refresh_token || credential.refresh_token,
      expires_at: token.expires_at
    }

    case Accounts.rotate_marvel_cdb_tokens(credential, params, actor: user) do
      {:ok, _updated} -> {:ok, token.access_token}
      {:error, reason} -> {:error, reason}
    end
  end

  defp expired?(%{expires_at: nil}), do: true

  defp expired?(%{expires_at: expires_at}) do
    deadline = DateTime.add(DateTime.utc_now(), @expiry_margin_seconds, :second)
    DateTime.compare(expires_at, deadline) != :gt
  end
end
