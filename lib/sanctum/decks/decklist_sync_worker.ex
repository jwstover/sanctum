defmodule Sanctum.Decks.DecklistSyncWorker do
  @moduledoc """
  Oban worker that runs the incremental decklist sync. Scheduled via the
  `Oban.Plugins.Cron` crontab in config; also enqueueable ad hoc.

  `unique` guarantees only one sync is ever in flight: a new job (from the hourly
  cron or an ad-hoc enqueue) is suppressed whenever one is already queued or
  executing, but a fresh run proceeds once the prior one reaches a terminal
  state. This matters because a single run mutates the shared sync cursor and
  makes a burst of MarvelCDB calls — two at once would race and double the load.
  Uniqueness is keyed on `[:worker, :queue]` (not `:args`) so an ad-hoc
  `since` backfill still debounces against the plain hourly run rather than
  racing it.

  Optional job args:

    * `"since"` — an ISO-8601 date string (`"2024-01-01"`). Runs a historical
      backfill from that day to today instead of resuming from the stored
      cursor. A historical `since` never rewinds the cursor (see `DeckSync`),
      so it's a safe way to re-walk and pick up decks a past run missed.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [fields: [:worker, :queue], period: :infinity, states: :incomplete]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    # Route progress into the Monitor so the admin dashboard can watch the run
    # live (and see its outcome afterward); the Monitor also handles logging.
    opts = maybe_put_since([progress_fun: &Sanctum.DeckSync.Monitor.report/1], args)
    result = Sanctum.DeckSync.run(opts)

    # Uniqueness recompute is left to the nightly ComputeUniquenessWorker cron:
    # enqueueing it after every sync run meant the full-library sweep (a
    # multi-million-row read plus an UPDATE over every deck) ran near-constantly
    # during the backfill — every halted-and-retried hourly run with any imports
    # triggered another sweep — saturating the shared database. Newly synced
    # decks just show as unranked until the next nightly sweep.

    case result do
      {:ok, _summary} ->
        :ok

      {:error, summary} ->
        # A transient fetch failure halted the run. Fail the job so Oban retries
        # with backoff; the cursor was checkpointed at the last good day, so the
        # retry resumes there rather than re-walking the whole range.
        {:error, "deck sync halted at #{summary.halted.date}: #{inspect(summary.halted.reason)}"}
    end
  end

  # Oban serializes args to JSON, so `since` arrives as a string. A malformed
  # value is ignored (falls back to a normal cursor-resuming run) rather than
  # failing the job.
  defp maybe_put_since(opts, %{"since" => since}) when is_binary(since) do
    case Date.from_iso8601(since) do
      {:ok, date} -> Keyword.put(opts, :since, date)
      {:error, _} -> opts
    end
  end

  defp maybe_put_since(opts, _args), do: opts
end
