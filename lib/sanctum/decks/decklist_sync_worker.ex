defmodule Sanctum.Decks.DecklistSyncWorker do
  @moduledoc """
  Oban worker that runs the incremental decklist sync. Scheduled via the
  `Oban.Plugins.Cron` crontab in config; also enqueueable ad hoc.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

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
