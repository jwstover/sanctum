defmodule Sanctum.Games.CardPoolCount do
  @moduledoc """
  Cached total-count of the browsable card pool for the "/ N cards" denominator
  on `SanctumWeb.CardLive.Pool`.

  `total` is the full **unfiltered** catalog size for the current viewer — it
  must never be derived from a filtered load (arriving at `/cards` from the
  global search seeds the page with a query, so the first load is already
  filtered; taking its count as the total is what produced the "4161 / 15"
  bug). The catalog only changes on a card sync, so the count is memoised
  per-node in `:persistent_term` with a short TTL, keyed by everything that can
  change which rows a viewer may see (browse `scope` + actor). Mirrors the
  `Sanctum.Search.ValueCache` approach — no invalidation wiring, lazy refresh.

  The loader runs in the calling process (the LiveView's async task), so the
  Ecto sandbox connection ownership just works in tests.
  """

  require Ash.Query

  alias Sanctum.Games.CardSide

  @default_ttl :timer.minutes(10)

  # Overridable per-env: config/test.exs sets it to 0 so every fetch recomputes
  # against the calling test's Ecto sandbox instead of leaking a count between
  # `async: true` tests that share this node-global `:persistent_term`.
  defp ttl_default, do: Application.get_env(:sanctum, __MODULE__, [])[:ttl] || @default_ttl

  @doc """
  Return the cached unfiltered pool count for `actor` + `scope`, running the
  count query (and caching it) when the entry is missing or expired.

  Returns `nil` if the count query fails, so the LiveView degrades to its
  loading state instead of crashing.
  """
  @spec total(term(), String.t() | nil, keyword()) :: non_neg_integer() | nil
  def total(actor, scope \\ nil, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, ttl_default())
    key = {actor_key(actor), scope}
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get({__MODULE__, key}, :miss) do
      {count, expires_at} when expires_at > now ->
        count

      _ ->
        load(key, actor, scope, now + ttl)
    end
  end

  @doc "Drop every cached count (used by tests and after manual syncs)."
  @spec reset() :: :ok
  def reset do
    for {{__MODULE__, _key} = key, _value} <- :persistent_term.get() do
      :persistent_term.erase(key)
    end

    :ok
  end

  defp load(key, actor, scope, expires_at) do
    count =
      CardSide
      |> Ash.Query.for_read(:browse, %{scope: scope}, actor: actor)
      |> Ash.count!()

    :persistent_term.put({__MODULE__, key}, {count, expires_at})
    count
  rescue
    error ->
      require Logger

      Logger.warning("card pool count loader failed: #{Exception.message(error)}")

      nil
  end

  # Actor visibility only differs by the actor's own homebrew, so keying by id
  # (nil when anonymous) is enough to keep distinct viewers from sharing a count.
  defp actor_key(%{id: id}), do: id
  defp actor_key(_), do: nil
end
