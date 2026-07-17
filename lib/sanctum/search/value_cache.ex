defmodule Sanctum.Search.ValueCache do
  @moduledoc """
  A tiny per-node TTL cache for autocomplete value lists (traits, sets,
  packs, hero names).

  These vocabularies are small (tens to a few hundred short strings) and only
  change on a card sync or deck import, so they're kept in memory via
  `:persistent_term` and lazily refreshed after a TTL — no invalidation
  wiring, no supervision. Writes are infrequent (once per key per TTL), which
  is exactly the access pattern `:persistent_term` wants.

  The loader runs in the calling process (the LiveView handling the suggest
  event), so in tests the Ecto sandbox connection ownership just works.
  """

  @default_ttl :timer.minutes(10)

  @doc """
  Return the cached values for `key`, running `loader` (and caching its
  result) when the entry is missing or older than `:ttl` milliseconds.

  If the loader raises, the error is logged and `[]` is returned uncached, so
  a transient DB problem degrades autocomplete instead of crashing the
  LiveView.
  """
  @spec fetch(term(), (-> [String.t()]), keyword()) :: [String.t()]
  def fetch(key, loader, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get({__MODULE__, key}, :miss) do
      {values, expires_at} when expires_at > now ->
        values

      _ ->
        load(key, loader, now + ttl)
    end
  end

  @doc "Drop every cached value list (used by tests and after manual syncs)."
  @spec reset() :: :ok
  def reset do
    for {{__MODULE__, _key} = key, _value} <- :persistent_term.get() do
      :persistent_term.erase(key)
    end

    :ok
  end

  defp load(key, loader, expires_at) do
    values = loader.()
    :persistent_term.put({__MODULE__, key}, {values, expires_at})
    values
  rescue
    error ->
      require Logger

      Logger.warning(
        "search value cache loader for #{inspect(key)} failed: #{Exception.message(error)}"
      )

      []
  end
end
