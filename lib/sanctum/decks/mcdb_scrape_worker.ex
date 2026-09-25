defmodule Sanctum.Decks.McdbScrapeWorker do
  @moduledoc """
  Oban worker driving the one-time MarvelCDB list-page sweep (see
  `Sanctum.Decks.McdbScrape`). The sweep is self-chaining: each job fetches,
  applies, and records one list page, then enqueues the next page. It's
  resumable because the cursor (`page`, `sort`, `started_at`) lives entirely
  in the job args, not in process state.

  The chain insert (in `McdbScrape.run_page/3`) passes `unique: false`. The
  running job is `executing`, which counts as `:incomplete` for this
  worker's own uniqueness constraint below — a unique insert for the next
  page would conflict with the very job that's inserting it and silently end
  the sweep after page 1. The admin/Release entry point
  (`McdbScrape.start/1`) keeps the default uniqueness, and because the Basic
  engine checks uniqueness by query (not by a flag on the inserting row), it
  still debounces a fresh `start/1` call against whatever page is currently
  chained — at most one sweep job is ever in flight.

  Pacing happens by scheduling the next job (`schedule_in`) rather than
  sleeping inside `perform/1`: jobs stay short, a redeploy never orphans a
  sleeping job, and a scheduled job is still `:incomplete`, so uniqueness
  keeps holding between pages.

  Multi-machine safety: the `:mcdb_scrape` queue's `limit: 1` is per node,
  but there is only ever one sweep job in flight across the whole cluster
  (unique on `start/1`, one chained successor per page), so at most one page
  runs at a time no matter how many machines are up.
  """

  use Oban.Worker,
    queue: :mcdb_scrape,
    max_attempts: 10,
    unique: [fields: [:worker, :queue], period: :infinity, states: :incomplete]

  alias Sanctum.Decks.McdbScrape

  @impl Oban.Worker
  def perform(
        %Oban.Job{args: %{"page" => page, "sort" => sort, "started_at" => started_at}} = job
      ) do
    with {:ok, sort_atom} <- parse_sort(sort),
         {:ok, parsed_started_at, _offset} <- DateTime.from_iso8601(started_at) do
      run(job, page, sort_atom, parsed_started_at)
    else
      {:error, reason} -> {:error, "MCDB sweep page #{page}: bad args (#{inspect(reason)})"}
    end
  end

  defp run(job, page, sort, started_at) do
    case McdbScrape.run_page(page, sort, started_at) do
      :ok ->
        :ok

      {:error, reason} ->
        if job.attempt >= job.max_attempts do
          McdbScrape.mark_failed(page, reason)
        else
          McdbScrape.record_error(page, reason)
        end

        {:error, "MCDB sweep page #{page}: #{inspect(reason)}"}
    end
  end

  # Capped exponential backoff (~2m, 4m, 8m, … capped at 1h): Req's own
  # `:transient` retry already smooths out quick blips, so by the time a page
  # fails all the way out to Oban, MarvelCDB is likely rate-limiting or down —
  # back off hard rather than hammering it every few seconds.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: min(60 * Integer.pow(2, attempt), 3600)

  defp parse_sort("date"), do: {:ok, :date}
  defp parse_sort("likes"), do: {:ok, :likes}
  defp parse_sort(other), do: {:error, {:bad_sort, other}}
end
