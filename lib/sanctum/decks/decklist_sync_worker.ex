defmodule Sanctum.Decks.DecklistSyncWorker do
  @moduledoc """
  Oban worker that runs the incremental decklist sync. Scheduled via the
  `Oban.Plugins.Cron` crontab in config; also enqueueable ad hoc.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  @impl Oban.Worker
  def perform(_job) do
    with {:ok, _summary} <- Sanctum.DeckSync.run() do
      :ok
    end
  end
end
