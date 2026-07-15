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
    with {:ok, summary} <- Sanctum.DeckSync.run() do
      # New decks shift their heroes' uniqueness rankings; recompute. `unique`
      # on the worker debounces this against the nightly cron run.
      if summary.imported > 0 do
        Sanctum.Decks.ComputeUniquenessWorker.new(%{}) |> Oban.insert()
      end

      :ok
    end
  end
end
