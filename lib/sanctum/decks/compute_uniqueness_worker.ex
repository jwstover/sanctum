defmodule Sanctum.Decks.ComputeUniquenessWorker do
  @moduledoc """
  Oban worker that recomputes deck uniqueness across the whole library.

  Scheduled nightly via the `Oban.Plugins.Cron` crontab and enqueued after a
  decklist sync. `unique` debounces bursts (e.g. a bulk import) so overlapping
  enqueues collapse into a single sweep.
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 300]

  @impl Oban.Worker
  def perform(_job) do
    with {:ok, _summary} <- Sanctum.Decks.Uniqueness.recompute_all() do
      :ok
    end
  end
end
