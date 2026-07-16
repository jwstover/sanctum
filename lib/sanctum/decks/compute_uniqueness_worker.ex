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
    started_at = System.monotonic_time(:millisecond)

    with {:ok, %{decks: decks, ranked: ranked}} <- Sanctum.Decks.Uniqueness.recompute_all() do
      :telemetry.execute(
        [:sanctum, :uniqueness, :recompute, :stop],
        %{
          duration_ms: System.monotonic_time(:millisecond) - started_at,
          decks: decks,
          ranked: ranked
        },
        %{}
      )

      :ok
    end
  end
end
