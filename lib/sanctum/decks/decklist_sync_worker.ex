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
    max_attempts: 3,
    unique: [period: :infinity, states: :incomplete]

  @impl Oban.Worker
  def perform(_job) do
    # Route progress into the Monitor so the admin dashboard can watch the run
    # live (and see its outcome afterward); the Monitor also handles logging.
    result = Sanctum.DeckSync.run(progress_fun: &Sanctum.DeckSync.Monitor.report/1)
    summary = elem(result, 1)

    # New decks shift their heroes' uniqueness rankings; recompute. Do this even
    # for a halted run — partial progress still imports decks. `unique` on the
    # worker debounces this against the nightly cron run.
    if summary.imported > 0 do
      Sanctum.Decks.ComputeUniquenessWorker.new(%{}) |> Oban.insert()
    end

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
