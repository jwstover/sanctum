defmodule Sanctum.Games.CardOfTheDay do
  @moduledoc """
  The homepage's daily player card: everyone sees the same card all day
  (UTC), and it rotates at midnight. The date hashes into an offset over the
  stable-sorted `:daily_pool` read, so no picked-card state is stored — the
  same date always resolves to the same card (until the catalog grows, which
  merely reshuffles future days).
  """

  require Ash.Query

  alias Sanctum.Games.Card

  @doc """
  The card of the day for `date` (defaults to today, UTC), with its primary
  side loaded. Returns `nil` when the pool is empty (e.g. before a card sync).
  """
  def for_date(date \\ Date.utc_today()) do
    pick(:daily_pool, {:card_of_the_day, date})
  end

  @doc """
  The daily Flavor Town teaser: a card from the guessing game's own pool
  (`:guessable` — any official card with flavor text), picked the same
  deterministic way under a different hash salt. Callers should show only the
  flavor text — the name is the game's answer.
  """
  def flavor_teaser(date \\ Date.utc_today()) do
    pick(:guessable, {:flavor_of_the_day, date})
  end

  # Hashes the seed into an offset over the action's rows. The explicit sort
  # keeps the offset deterministic for reads (like :guessable) that don't
  # declare one themselves.
  defp pick(action, seed) do
    count =
      Card
      |> Ash.Query.for_read(action)
      |> Ash.read!(page: [limit: 1, offset: 0, count: true])
      |> Map.get(:count)

    if is_integer(count) and count > 0 do
      offset = :erlang.phash2(seed, count)

      Card
      |> Ash.Query.for_read(action)
      |> Ash.Query.sort(base_code: :asc)
      |> Ash.read!(page: [limit: 1, offset: offset])
      |> Map.get(:results)
      |> List.first()
    end
  end
end
