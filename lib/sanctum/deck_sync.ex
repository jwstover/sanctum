defmodule Sanctum.DeckSync do
  @moduledoc """
  Incrementally mirrors MarvelCDB's published decklists into Sanctum.

  Walks each date from the stored cursor (`Sanctum.Decks.DeckSyncState`)
  through today, importing every decklist via `Sanctum.MarvelCdb.import_decklist/2`.
  Imports upsert on `[:mcdb_type, :mcdb_id]`, so re-running is idempotent; each
  run also re-scans a small trailing window to catch late-arriving decks before
  advancing the cursor.

  The cursor is checkpointed *after every day that succeeds* — a 404 (no decks
  that day) counts as success, but a transient fetch failure (timeout /
  rate-limit / a 5xx that reflects a real outage) **halts the run** and leaves
  the cursor at the last good day. `run/1` then returns `{:error, summary}` so
  the caller (the Oban worker) can fail and retry, resuming from the checkpoint.
  This keeps a slow or flaky MarvelCDB from silently skipping days.

  Checkpointing per day (rather than once at the end of the run) is what makes an
  *abrupt* stop recoverable: an Oban timeout, a deploy restart, or an uncaught
  crash bypasses any end-of-run bookkeeping, so a run that only persisted its
  progress at the finish line would resume from where it *started*. Persisting
  each successful day means a killed backfill resumes within one day of where it
  died instead of re-walking years of history.

  One wrinkle: MarvelCDB answers `by_date` for a day with no decklists with an
  HTTP 500 rather than a 404. `sync_date/2` disambiguates that benign case from
  a genuine outage by canary-probing the endpoint's health, so an empty day
  doesn't wedge the walk (see `MarvelCdb.decklists_endpoint_healthy?/0`).

  Entry points: `mix sanctum.sync_decks` (manual/backfill) and
  `Sanctum.Decks.DecklistSyncWorker` (scheduled via Oban Cron).
  """

  require Logger

  alias Sanctum.Decks
  alias Sanctum.MarvelCdb

  # MarvelCDB launched in late 2019; used as the backfill floor when no cursor
  # exists and no `:since` is given. (Empty early days that MarvelCDB answers
  # with a 500 are handled in `sync_date/2`, so the floor no longer needs to
  # dodge them.)
  @default_start_date ~D[2019-11-01]

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

    initial = %{imported: 0, failed: 0, processed: 0, halted: nil}

    # Snapshot the cursor once, up front. The worker's `unique` lock means no
    # other run can move it underneath us, and days are walked in increasing
    # order — so any day past this frontier is a genuine advance we checkpoint
    # immediately, while a historical `--since` backfill of older days never
    # rewinds it.
    frontier = current_cursor()

    acc =
      Enum.reduce_while(dates, initial, fn date, acc ->
        case sync_date(date, progress) do
          {:ok, imported, failed} ->
            # Persist the cursor the moment a day succeeds so an abrupt stop (an
            # orphaned-then-rescued job, a deploy restart, an uncaught crash)
            # resumes within a day of here instead of re-walking from the last
            # completed run's checkpoint.
            checkpoint_day(date, frontier)

            {:cont,
             %{
               acc
               | imported: acc.imported + imported,
                 failed: acc.failed + failed,
                 processed: acc.processed + 1
             }}

          {:error, reason} ->
            # A transient fetch failure (timeout / 5xx / rate-limit): stop the
            # walk so the cursor never advances past a day we couldn't fetch.
            {:halt, %{acc | halted: %{date: date, reason: reason}}}
        end
      end)

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

  # Advance the cursor to a day we just fetched successfully, but never rewind
  # it: a historical `--since` backfill of old dates (behind `frontier`) must not
  # drag the frontier backward. `frontier` is the run-start cursor; a nil frontier
  # means no cursor existed yet, so every synced day advances it.
  defp checkpoint_day(%Date{} = date, frontier) do
    if frontier == nil or Date.compare(date, frontier) == :gt do
      {:ok, _state} = Decks.set_last_synced_date(date)
    end

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

      # MarvelCDB returns HTTP 500 (not 404) for dates with no decklists — a
      # quirk scattered across historical days. Halting on every 500 wedges the
      # backfill on the first empty day, so disambiguate: if the endpoint is
      # otherwise healthy (a canary date still serves data), this 500 means "no
      # decks that day" — treat it as an empty day and advance. Only a 500 that
      # coincides with an unhealthy endpoint (a real outage) halts the run, so
      # the cursor never skips days that actually have decks.
      {:error, {:server_error, status}} ->
        if MarvelCdb.decklists_endpoint_healthy?() do
          Logger.info(
            "Deck sync #{date}: MarvelCDB #{status}, endpoint healthy — treating as empty day"
          )

          progress.({:date, %{date: date, imported: 0, failed: 0}})
          Process.sleep(@download_pause_ms)
          {:ok, 0, 0}
        else
          progress.({:date_error, %{date: date, reason: {:server_error, status}}})
          {:error, "Unexpected status code: #{status}"}
        end

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
      Sentry.capture_exception(exception, stacktrace: __STACKTRACE__)
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
