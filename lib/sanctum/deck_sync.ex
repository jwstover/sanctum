defmodule Sanctum.DeckSync do
  @moduledoc """
  Incrementally mirrors MarvelCDB's published decklists into Sanctum.

  Walks each date from the stored cursor (`Sanctum.Decks.DeckSyncState`)
  through today, importing every decklist via `Sanctum.MarvelCdb.import_decklist/2`.
  Imports upsert on `[:mcdb_type, :mcdb_id]`, so re-running is idempotent; each
  run also re-scans a small trailing window to catch late-arriving decks before
  advancing the cursor.

  The cursor is checkpointed at the last day fetched *successfully* — a 404 (no
  decks that day) counts as success, but a transient fetch failure (timeout /
  5xx / rate-limit) **halts the run** and leaves the cursor at the last good
  day. `run/1` then returns `{:error, summary}` so the caller (the Oban worker)
  can fail and retry, resuming from the checkpoint. This keeps a slow or flaky
  MarvelCDB from silently skipping days.

  Entry points: `mix sanctum.sync_decks` (manual/backfill) and
  `Sanctum.Decks.DecklistSyncWorker` (scheduled via Oban Cron).
  """

  require Logger

  alias Sanctum.Decks
  alias Sanctum.MarvelCdb

  # MarvelCDB launched in late 2019; used as the backfill floor when no cursor
  # exists and no `:since` is given. Floored at 2019-11-02 rather than 11-01
  # because MarvelCDB's `/decklists/by_date/2019-11-01` endpoint permanently
  # returns HTTP 500 (a server-side bug on that single earliest date). Since a
  # 5xx halts the run to avoid skipping days, starting on 11-01 wedged the sync
  # on day one forever; 11-01 holds no fetchable decks anyway.
  @default_start_date ~D[2019-11-02]

  # Re-scan this many days before the cursor each run, so decks published late
  # (or edited on) a day that was already synced still get picked up.
  @overlap_days 1

  # Be polite between day requests, matching the card sync's pacing.
  @download_pause_ms 200

  # Brief yield between deck imports so a burst (a busy day, or a backfill)
  # doesn't monopolize the database — on Neon's small shared compute a
  # back-to-back import stream visibly delays interactive queries.
  @deck_pause_ms 50

  @doc """
  Runs the sync. Options:

    * `:since` — `Date` to start from (overrides the stored cursor)
    * `:until` — `Date` to stop at (default: today, UTC)
    * `:progress_fun` — `fun/1` receiving progress events; defaults to
      CLI-style logging

  Returns `{:ok, summary}` when the whole range was fetched, or `{:error,
  summary}` when a transient failure halted it early. `summary` is a map of
  `%{days, processed, imported, failed, halted}` where `halted` is `nil` or
  `%{date, reason}`.
  """
  def run(opts \\ []) do
    progress = Keyword.get(opts, :progress_fun, &log_progress/1)
    start_date = start_date(opts)
    until = Keyword.get(opts, :until, Date.utc_today())

    dates = date_range(start_date, until)
    progress.({:started, %{from: start_date, to: until, days: length(dates)}})

    initial = %{imported: 0, failed: 0, processed: 0, last_ok: nil, halted: nil}

    acc =
      Enum.reduce_while(dates, initial, fn date, acc ->
        case sync_date(date, progress) do
          {:ok, imported, failed} ->
            {:cont,
             %{
               acc
               | imported: acc.imported + imported,
                 failed: acc.failed + failed,
                 processed: acc.processed + 1,
                 last_ok: date
             }}

          {:error, reason} ->
            # A transient fetch failure (timeout / 5xx / rate-limit): stop the
            # walk so the cursor never advances past a day we couldn't fetch.
            {:halt, %{acc | halted: %{date: date, reason: reason}}}
        end
      end)

    checkpoint_cursor(acc.last_ok)

    summary = %{
      days: length(dates),
      processed: acc.processed,
      imported: acc.imported,
      failed: acc.failed,
      halted: acc.halted
    }

    progress.({:done, summary})

    if acc.halted, do: {:error, summary}, else: {:ok, summary}
  end

  # Advance the cursor to the last day we successfully fetched, but never rewind
  # it: a halted run or a historical `--since` backfill of old dates must not
  # drag the frontier backward. Nothing fetched (nil) leaves the cursor as-is.
  defp checkpoint_cursor(nil), do: :ok

  defp checkpoint_cursor(%Date{} = last_ok) do
    advance? =
      case current_cursor() do
        %Date{} = cursor -> Date.compare(last_ok, cursor) == :gt
        nil -> true
      end

    if advance?, do: {:ok, _state} = Decks.set_last_synced_date(last_ok)
    :ok
  end

  defp sync_date(date, progress) do
    case MarvelCdb.get_decklists_by_date(date) do
      {:ok, decklists} ->
        result = import_decklists(decklists, date, progress)
        progress.({:date, Map.put(result, :date, date)})
        Process.sleep(@download_pause_ms)
        {:ok, result.imported, result.failed}

      # 404 means MarvelCDB simply has no decklists for this date — a normal,
      # permanent outcome, not a failure. Record an empty day and keep going.
      {:error, :not_found} ->
        progress.({:date, %{date: date, imported: 0, failed: 0}})
        Process.sleep(@download_pause_ms)
        {:ok, 0, 0}

      {:error, reason} ->
        progress.({:date_error, %{date: date, reason: reason}})
        {:error, reason}
    end
  end

  defp import_decklists(decklists, date, progress) do
    Enum.reduce(decklists, %{imported: 0, failed: 0}, fn decklist, acc ->
      Process.sleep(@deck_pause_ms)

      case import_one(decklist) do
        {:ok, _deck} ->
          progress.({:deck, %{date: date, name: decklist["name"], ok?: true}})
          Map.update!(acc, :imported, &(&1 + 1))

        {:error, reason} ->
          Logger.warning("Failed to import decklist #{decklist["id"]}: #{inspect(reason)}")
          progress.({:deck, %{date: date, name: decklist["name"], ok?: false}})
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

  defp log_progress({:done, %{halted: %{date: date, reason: reason}} = s}),
    do:
      Logger.warning(
        "Deck sync halted at #{date} (#{inspect(reason)}) after #{s.processed} day(s): " <>
          "#{s.imported} imported, #{s.failed} failed"
      )

  defp log_progress({:done, %{days: days, imported: imported, failed: failed}}),
    do: Logger.info("Deck sync done: #{days} days, #{imported} imported, #{failed} failed")

  defp log_progress(_event), do: :ok
end
