defmodule Sanctum.DeckSync do
  @moduledoc """
  Incrementally mirrors MarvelCDB's published decklists into Sanctum.

  Walks each date from the stored cursor (`Sanctum.Decks.DeckSyncState`)
  through today, importing every decklist via `Sanctum.MarvelCdb.import_decklist/2`.
  Imports upsert on `[:mcdb_type, :mcdb_id]`, so re-running is idempotent; each
  run also re-scans a small trailing window to catch late-arriving decks before
  advancing the cursor.

  Entry points: `mix sanctum.sync_decks` (manual/backfill) and
  `Sanctum.Decks.DecklistSyncWorker` (scheduled via Oban Cron).
  """

  require Logger

  alias Sanctum.Decks
  alias Sanctum.MarvelCdb

  # MarvelCDB launched in late 2019; used as the backfill floor when no cursor
  # exists and no `:since` is given.
  @default_start_date ~D[2019-11-01]

  # Re-scan this many days before the cursor each run, so decks published late
  # (or edited on) a day that was already synced still get picked up.
  @overlap_days 1

  # Be polite between day requests, matching the card sync's pacing.
  @download_pause_ms 200

  @doc """
  Runs the sync. Options:

    * `:since` — `Date` to start from (overrides the stored cursor)
    * `:until` — `Date` to stop at (default: today, UTC)
    * `:progress_fun` — `fun/1` receiving progress events; defaults to
      CLI-style logging

  Returns `{:ok, %{days, imported, failed}}`.
  """
  def run(opts \\ []) do
    progress = Keyword.get(opts, :progress_fun, &log_progress/1)
    start_date = start_date(opts)
    until = Keyword.get(opts, :until, Date.utc_today())

    dates = date_range(start_date, until)
    progress.({:started, %{from: start_date, to: until, days: length(dates)}})

    {imported, failed} =
      Enum.reduce(dates, {0, 0}, fn date, {imported, failed} ->
        {di, df} = sync_date(date, progress)
        {imported + di, failed + df}
      end)

    {:ok, _state} = Decks.set_last_synced_date(until)

    summary = %{days: length(dates), imported: imported, failed: failed}
    progress.({:done, summary})
    {:ok, summary}
  end

  defp sync_date(date, progress) do
    case MarvelCdb.get_decklists_by_date(date) do
      {:ok, decklists} ->
        result = import_decklists(decklists)
        progress.({:date, Map.put(result, :date, date)})
        Process.sleep(@download_pause_ms)
        {result.imported, result.failed}

      {:error, reason} ->
        progress.({:date_error, %{date: date, reason: reason}})
        {0, 0}
    end
  end

  defp import_decklists(decklists) do
    Enum.reduce(decklists, %{imported: 0, failed: 0}, fn decklist, acc ->
      case import_one(decklist) do
        {:ok, _deck} ->
          Map.update!(acc, :imported, &(&1 + 1))

        {:error, reason} ->
          Logger.warning("Failed to import decklist #{decklist["id"]}: #{inspect(reason)}")
          Map.update!(acc, :failed, &(&1 + 1))
      end
    end)
  end

  # A single malformed deck must never abort the whole run: import_decklist can
  # raise (e.g. a hero_code whose card isn't in the catalog yet), not just return
  # `{:error, _}`, so rescue and treat any raise as a per-deck failure.
  defp import_one(decklist) do
    MarvelCdb.import_decklist(decklist, mcdb_type: :decklist)
  rescue
    exception ->
      {:error, Exception.format(:error, exception, __STACKTRACE__)}
  end

  # `:since` wins; otherwise resume one overlap window before the cursor; else
  # fall back to the backfill floor.
  defp start_date(opts) do
    cond do
      since = Keyword.get(opts, :since) -> since
      cursor = current_cursor() -> Date.add(cursor, -@overlap_days)
      true -> @default_start_date
    end
  end

  defp current_cursor do
    case Decks.get_deck_sync_state() do
      {:ok, %{last_synced_date: %Date{} = date}} -> date
      _ -> nil
    end
  end

  defp date_range(start_date, until) do
    if Date.compare(start_date, until) == :gt do
      []
    else
      Date.range(start_date, until) |> Enum.to_list()
    end
  end

  defp log_progress({:started, %{from: from, to: to, days: days}}),
    do: Logger.info("Syncing decklists from #{from} to #{to} (#{days} days)...")

  defp log_progress({:date, %{date: date, imported: imported, failed: failed}}),
    do: Logger.info("  #{date}: #{imported} imported, #{failed} failed")

  defp log_progress({:date_error, %{date: date, reason: reason}}),
    do: Logger.warning("  #{date}: fetch failed: #{inspect(reason)}")

  defp log_progress({:done, %{days: days, imported: imported, failed: failed}}),
    do: Logger.info("Deck sync done: #{days} days, #{imported} imported, #{failed} failed")

  defp log_progress(_event), do: :ok
end
