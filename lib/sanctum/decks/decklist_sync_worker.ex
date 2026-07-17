defmodule Sanctum.Decks.DecklistSyncWorker do
  @moduledoc """
  Oban worker that runs the incremental decklist sync. Scheduled via the
  `Oban.Plugins.Cron` crontab in config; also enqueueable ad hoc.

  `unique` guarantees only one sync is ever in flight: a new job (from the hourly
  cron or an ad-hoc enqueue) is suppressed whenever one is already queued or
  executing, but a fresh run proceeds once the prior one reaches a terminal
  state. This matters because a single run mutates the shared sync cursor and
  makes a burst of MarvelCDB calls — two at once would race and double the load.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete]

  @impl Oban.Worker
  def perform(_job) do
    # Route progress into the Monitor so the admin dashboard can watch the run
    # live (and see its outcome afterward); the Monitor also handles logging.
    result = Sanctum.DeckSync.run(progress_fun: &Sanctum.DeckSync.Monitor.report/1)

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
end
