defmodule Sanctum.Decks.McdbSocialRefreshWorker do
  @moduledoc """
  Oban worker that runs the daily MarvelCDB social refresh (see
  `Sanctum.Decks.McdbSocialRefresh`). Scheduled via the `Oban.Plugins.Cron`
  crontab in config.

  Unlike the one-time backfill sweep, this is a single job that walks all of
  its pages itself, sleeping between them: at 85 pages or fewer that's about
  six minutes, well short of anything worth self-chaining like the backfill
  does. A redeploy mid-run gets rescued by `Sanctum.Oban.BootRescue` or the
  Lifeline plugin and simply reruns from page 1 on the next cron tick or
  rescue — the refresh is idempotent, so that's harmless.

  Runs on the shared `:mcdb_scrape` queue (`limit: 1`), so on a single node it
  never overlaps a backfill page; `McdbSocialRefresh.run/1` also checks
  `oban_jobs` itself for the backfill worker, which covers a multi-machine
  deploy where the queue's `limit` is only enforced per node.

  `unique` on `[:worker, :queue]` keeps a slow run from stacking with the next
  day's cron tick.
  """

  use Oban.Worker,
    queue: :mcdb_scrape,
    max_attempts: 3,
    unique: [fields: [:worker, :queue], period: :infinity, states: :incomplete]

  alias Sanctum.Decks.McdbSocialRefresh

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case McdbSocialRefresh.run() do
      {:ok, _summary} -> :ok
      {:skipped, :backfill_running} -> :ok
      {:error, reason} -> {:error, "MCDB social refresh halted: #{inspect(reason)}"}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)
end
