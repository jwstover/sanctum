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
    count =
      Card
      |> Ash.Query.for_read(:daily_pool)
      |> Ash.read!(page: [limit: 1, offset: 0, count: true])
      |> Map.get(:count)

    if is_integer(count) and count > 0 do
      offset = :erlang.phash2({:card_of_the_day, date}, count)

      Card
      |> Ash.Query.for_read(:daily_pool)
      |> Ash.read!(page: [limit: 1, offset: offset])
      |> Map.get(:results)
      |> List.first()
    end
  end
end
