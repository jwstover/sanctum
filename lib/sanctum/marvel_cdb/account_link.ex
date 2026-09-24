defmodule Sanctum.MarvelCdb.AccountLink do
  @moduledoc """
  Links a signed-in Sanctum user to the MarvelCDB account behind an OAuth
  grant.

  MarvelCDB's OAuth API has no user-info endpoint, so there is no `uid` to
  key on the way a normal OAuth strategy would — the account id only ever
  shows up as the `user_id` MarvelCDB stamps on the owner's own decks (see
  `Sanctum.MarvelCdb.OAuth.owner_id/1`). No decks means no id: the credential
  is still stored, but nothing gets linked until a later connect finds decks
  to read the id from.
  """

  require Logger

  alias Sanctum.Decks
  alias Sanctum.MarvelCdb.Credentials
  alias Sanctum.MarvelCdb.OAuth

  @doc "Resolves the MarvelCDB account id owning this access token."
  @spec identify(String.t()) :: {:ok, integer()} | {:error, term()}
  def identify(access_token), do: OAuth.owner_id(access_token)

  @doc """
  Claims a MarvelCDB account (by its numeric id) on behalf of `user`.

  Preserves an existing username (no username is passed to
  `find_or_create_mcdb_user`), and refuses with `{:error, :claimed_by_other}`
  if the account already belongs to a different Sanctum user — checked both
  up front and via the policy, which covers a race between the check and the
  write.
  """
  @spec claim(struct(), integer()) :: {:ok, struct()} | {:error, :claimed_by_other | term()}
  def claim(user, mcdb_user_id) do
    with {:ok, mcdb_user} <- Decks.find_or_create_mcdb_user(%{mcdb_user_id: mcdb_user_id}),
         :ok <- check_unclaimed(mcdb_user, user) do
      do_claim(mcdb_user, user)
    end
  end

  defp do_claim(mcdb_user, user) do
    case Decks.claim_mcdb_user(mcdb_user, actor: user) do
      {:ok, claimed} -> {:ok, claimed}
      {:error, %Ash.Error.Forbidden{}} -> {:error, :claimed_by_other}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stores a freshly exchanged token and links the account it belongs to, if
  identifiable yet.

  Order matters: the ownership check runs against `identify/1` *before*
  anything is persisted, so a conflicting account never gets a credential
  stored for it — any credential the user already had is left untouched.
  """
  @spec connect(struct(), map()) ::
          {:ok, {:linked, struct()} | {:unlinked, term()}} | {:error, term()}
  def connect(user, token) do
    case identify(token.access_token) do
      {:ok, mcdb_user_id} -> connect_and_claim(user, token, mcdb_user_id)
      {:error, reason} -> store_unlinked(user, token, reason)
    end
  end

  defp connect_and_claim(user, token, mcdb_user_id) do
    with {:ok, mcdb_user} <- Decks.find_or_create_mcdb_user(%{mcdb_user_id: mcdb_user_id}),
         :ok <- check_unclaimed(mcdb_user, user),
         {:ok, _credential} <- Credentials.connect(user, token) do
      finish_claim(mcdb_user, user)
    end
  end

  defp finish_claim(mcdb_user, user) do
    case Decks.claim_mcdb_user(mcdb_user, actor: user) do
      {:ok, claimed} ->
        {:ok, {:linked, claimed}}

      {:error, %Ash.Error.Forbidden{}} ->
        {:error, :claimed_by_other}

      {:error, reason} ->
        Logger.warning("MarvelCDB claim failed after connecting: #{inspect(reason)}")
        {:ok, {:unlinked, reason}}
    end
  end

  defp check_unclaimed(%{sanctum_user_id: id}, _user) when is_nil(id), do: :ok
  defp check_unclaimed(%{sanctum_user_id: id}, %{id: id}), do: :ok
  defp check_unclaimed(_mcdb_user, _user), do: {:error, :claimed_by_other}

  defp store_unlinked(user, token, reason) do
    with {:ok, _credential} <- Credentials.connect(user, token) do
      {:ok, {:unlinked, reason}}
    end
  end

  @doc """
  One-off backfill: walks every stored MarvelCDB credential and links it,
  the same way a fresh connect would. Safe to re-run — already-linked
  accounts just claim themselves again, a no-op under the policy.

  Never raises: every credential's outcome is caught and counted, so one bad
  or revoked grant can't stop the rest of the run.
  """
  @spec link_existing() :: %{
          linked: non_neg_integer(),
          unlinked: non_neg_integer(),
          conflicts: non_neg_integer(),
          errors: non_neg_integer()
        }
  def link_existing do
    Sanctum.Accounts.McdbCredential
    |> Ash.read!(authorize?: false, load: [:user])
    |> Enum.reduce(%{linked: 0, unlinked: 0, conflicts: 0, errors: 0}, fn credential, counts ->
      credential
      |> link_one()
      |> tally(counts)
    end)
  end

  defp link_one(credential) do
    user = credential.user

    with {:ok, access_token} <- Credentials.fetch_access_token(user),
         {:ok, mcdb_user_id} <- identify(access_token) do
      claim(user, mcdb_user_id)
    end
  end

  defp tally({:ok, mcdb_user}, counts) do
    Logger.info("Linked MarvelCDB account ##{mcdb_user.mcdb_user_id}")
    Map.update!(counts, :linked, &(&1 + 1))
  end

  defp tally({:error, :claimed_by_other}, counts) do
    Logger.warning("Skipped a MarvelCDB account already claimed by another user")
    Map.update!(counts, :conflicts, &(&1 + 1))
  end

  defp tally({:error, :no_decks}, counts) do
    Map.update!(counts, :unlinked, &(&1 + 1))
  end

  defp tally({:error, reason}, counts) do
    Logger.warning("Failed to link a MarvelCDB account: #{inspect(reason)}")
    Map.update!(counts, :errors, &(&1 + 1))
  end
end
