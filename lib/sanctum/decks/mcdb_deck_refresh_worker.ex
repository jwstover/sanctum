defmodule Sanctum.Decks.McdbDeckRefreshWorker do
  @moduledoc """
  Oban worker that runs one batch of the adaptive per-decklist like refresh
  (see `Sanctum.Decks.McdbDeckRefresh`). Scheduled hourly via the
  `Oban.Plugins.Cron` crontab in config.

  Shares the single-slot `:mcdb_scrape` queue with the backfill and daily
  social refresh. `unique` on `[:worker, :queue]` keeps a slow batch from
  stacking with the next tick. Idempotent and redeploy-safe: a rescued or
  rerun job just re-selects whatever is still due.
  """

  use Oban.Worker,
    queue: :mcdb_scrape,
    max_attempts: 3,
    unique: [fields: [:worker, :queue], period: :infinity, states: :incomplete]

  alias Sanctum.Decks.McdbDeckRefresh

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case McdbDeckRefresh.run() do
      {:ok, _summary} -> :ok
      {:skipped, _reason} -> :ok
      {:error, reason} -> {:error, "MCDB deck refresh halted: #{inspect(reason)}"}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(15)
end
