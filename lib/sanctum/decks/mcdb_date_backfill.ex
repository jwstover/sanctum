defmodule Sanctum.Decks.McdbDateBackfill do
  @moduledoc """
  One-time backfill of `mcdb_date_creation`/`mcdb_date_update` for decks that
  were imported before those fields were captured.

  Re-walks MarvelCDB's `by_date` endpoint like `Sanctum.DeckSync`, but instead
  of re-importing each deck it only copies the two date fields onto existing
  rows that are missing them — no hero resolution, no slot resolution, no
  deck_cards churn. Per day that's one HTTP request, one indexed read, and a
  handful of two-column updates, so the whole history costs minutes instead of
  a full re-sync. The by-date payload reflects each decklist's *current*
  `date_update`, so a creation-date walk still yields fresh values.

  The walk never touches the deck-sync cursor. A transient fetch failure
  (timeout / real outage) halts the run and reports the day it stopped at;
  re-run with `:since` set to that day to resume. MarvelCDB's empty-day 500
  quirk is disambiguated the same way `Sanctum.DeckSync` does it.

  Decks imported by URL (`mcdb_type: :deck`) live in a different id space that
  `by_date` can't reach — `run_private/1` re-imports those individually, which
  captures the dates now that `import_decklist` stores them.

  Entry points: `mix sanctum.backfill_deck_dates` (dev) and
  `Sanctum.Release.backfill_deck_dates()` (prod).
  """

  require Ash.Query
  require Logger

  alias Sanctum.Decks.Deck
  alias Sanctum.MarvelCdb

  # Matches Sanctum.DeckSync's backfill floor (MarvelCDB launch).
  @default_start_date ~D[2019-11-01]

  # Be polite between day requests, matching the deck sync's pacing.
  @download_pause_ms 200

  @doc """
  Backfills dates for `mcdb_type: :decklist` decks by walking `by_date`.

  Options:

    * `:since` — `Date` to start from (default: #{@default_start_date})
    * `:until` — `Date` to stop at (default: today, UTC)
    * `:progress_fun` — `fun/1` receiving progress events; defaults to
      CLI-style logging

  Returns `{:ok, summary}` or `{:error, summary}` when halted early; `summary`
  is `%{days, processed, updated, halted}` where `halted` is `nil` or
  `%{date, reason}`.
  """
  def run(opts \\ []) do
    progress = Keyword.get(opts, :progress_fun, &log_progress/1)
    since = Keyword.get(opts, :since, @default_start_date)
    until = Keyword.get(opts, :until, Date.utc_today())

    dates = date_range(since, until)
    progress.({:started, %{from: since, to: until, days: length(dates)}})

    acc =
      Enum.reduce_while(dates, %{processed: 0, updated: 0, halted: nil}, fn date, acc ->
        date |> backfill_date() |> handle_day(date, acc, progress)
      end)

    summary = %{
      days: length(dates),
      processed: acc.processed,
      updated: acc.updated,
      halted: acc.halted
    }

    progress.({:done, summary})

    if acc.halted, do: {:error, summary}, else: {:ok, summary}
  end

  @doc """
  Backfills dates for `mcdb_type: :deck` decks (private decks imported by URL)
  by re-importing each one through `MarvelCdb.load_deck/1`, which now captures
  the dates. A deck whose source object is gone from MarvelCDB is skipped and
  counted as failed.

  Returns `{:ok, %{updated, failed}}`.
  """
  def run_private(opts \\ []) do
    progress = Keyword.get(opts, :progress_fun, &log_progress/1)

    decks =
      Deck
      |> Ash.Query.filter(mcdb_type == :deck and is_nil(mcdb_date_update))
      |> Ash.Query.select([:id, :mcdb_id])
      |> Ash.read!(authorize?: false)

    progress.({:private_started, %{count: length(decks)}})

    summary =
      Enum.reduce(decks, %{updated: 0, failed: 0}, fn deck, acc ->
        Process.sleep(@download_pause_ms)

        # Route through the /deck endpoint (a bare id would be treated as a
        # decklist id — a different object in MarvelCDB's id space).
        case MarvelCdb.load_deck("https://marvelcdb.com/deck/view/#{deck.mcdb_id}") do
          {:ok, _deck} ->
            Map.update!(acc, :updated, &(&1 + 1))

          {:error, reason} ->
            Logger.warning(
              "Date backfill: re-import of deck #{deck.mcdb_id} failed: #{inspect(reason)}"
            )

            Map.update!(acc, :failed, &(&1 + 1))
        end
      end)

    progress.({:private_done, summary})

    {:ok, summary}
  end

  defp handle_day({:ok, updated}, date, acc, progress) do
    if updated > 0, do: progress.({:date, %{date: date, updated: updated}})
    Process.sleep(@download_pause_ms)
    {:cont, %{acc | processed: acc.processed + 1, updated: acc.updated + updated}}
  end

  defp handle_day({:error, reason}, date, acc, progress) do
    progress.({:date_error, %{date: date, reason: reason}})
    {:halt, %{acc | halted: %{date: date, reason: reason}}}
  end

  defp backfill_date(date) do
    case MarvelCdb.get_decklists_by_date(date) do
      {:ok, decklists} ->
        {:ok, apply_dates(decklists)}

      # No decklists that day.
      {:error, :not_found} ->
        {:ok, 0}

      # MarvelCDB's empty-day 500 quirk vs a real outage — same disambiguation
      # as Sanctum.DeckSync.
      {:error, {:server_error, status}} ->
        if MarvelCdb.decklists_endpoint_healthy?() do
          {:ok, 0}
        else
          {:error, "Unexpected status code: #{status}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_dates([]), do: 0

  defp apply_dates(decklists) do
    dates_by_id =
      Map.new(decklists, fn decklist ->
        {to_string(decklist["id"]),
         %{
           mcdb_date_creation: decklist["date_creation"],
           mcdb_date_update: decklist["date_update"]
         }}
      end)

    ids = Map.keys(dates_by_id)

    Deck
    |> Ash.Query.filter(mcdb_type == :decklist and mcdb_id in ^ids and is_nil(mcdb_date_update))
    |> Ash.Query.select([:id, :mcdb_id, :updated_at])
    |> Ash.read!(authorize?: false)
    |> Enum.map(fn deck ->
      Sanctum.Decks.set_deck_mcdb_dates!(deck, Map.fetch!(dates_by_id, deck.mcdb_id),
        authorize?: false
      )
    end)
    |> length()
  end

  defp date_range(since, until) do
    if Date.compare(since, until) == :gt do
      []
    else
      Date.range(since, until) |> Enum.to_list()
    end
  end

  defp log_progress({:started, %{from: from, to: to, days: days}}),
    do: Logger.info("Backfilling deck dates from #{from} to #{to} (#{days} days)...")

  defp log_progress({:date, %{date: date, updated: updated}}),
    do: Logger.info("  #{date}: #{updated} deck(s) updated")

  defp log_progress({:date_error, %{date: date, reason: reason}}),
    do: Logger.warning("  #{date}: fetch failed: #{inspect(reason)}")

  defp log_progress({:done, %{halted: %{date: date, reason: reason}} = s}),
    do:
      Logger.warning(
        "Date backfill halted at #{date} (#{inspect(reason)}) after #{s.processed} day(s): " <>
          "#{s.updated} updated. Re-run with since: ~D[#{date}] to resume."
      )

  defp log_progress({:done, %{days: days, updated: updated}}),
    do: Logger.info("Date backfill done: #{days} days, #{updated} deck(s) updated")

  defp log_progress({:private_started, %{count: count}}),
    do: Logger.info("Backfilling dates for #{count} private (URL-imported) deck(s)...")

  defp log_progress({:private_done, %{updated: updated, failed: failed}}),
    do: Logger.info("Private deck backfill done: #{updated} updated, #{failed} failed")

  defp log_progress(_event), do: :ok
end
