defmodule Sanctum.Decks.McdbScrape do
  @moduledoc """
  Drives the one-time, paced sweep of every MarvelCDB decklist list page
  (`/decklists/find/{page}`), filling in deck authors' usernames and like
  counts for decks that were imported before those fields existed.

  `Sanctum.Decks.McdbScrapeWorker` calls into this module one page at a time;
  this module owns the termination rule, the durable progress row
  (`Sanctum.Decks.McdbScrapeState`), and the post-sweep report.
  """

  require Ash.Query
  require Logger

  alias Sanctum.Decks
  alias Sanctum.Decks.Deck
  alias Sanctum.Decks.McdbScrapeWorker
  alias Sanctum.Decks.McdbUser
  alias Sanctum.MarvelCdb.DecklistPages
  alias Sanctum.Repo

  @type sort :: :date | :likes

  @state_fields [
    :status,
    :sort,
    :page,
    :last_page,
    :rows_seen,
    :matched,
    :unmatched,
    :users_updated,
    :started_at,
    :finished_at,
    :last_error,
    :missing_count
  ]

  @doc """
  Starts (or resumes) the sweep: the admin button and `Sanctum.Release`
  entry point. Inserts the first (or `page`) job with the worker's default
  uniqueness, so a second call while a sweep is already queued/executing
  returns `{:ok, %Oban.Job{conflict?: true}}` instead of starting a second
  sweep. Callers must check `job.conflict?`.

  `resume: true` (used when resuming a `:failed` sweep from `page`) keeps the
  existing counters and `started_at`, so the missing-deck report at the end
  still measures the whole sweep rather than just the resumed tail.
  """
  @spec start(keyword()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def start(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    sort = to_sort_atom(Keyword.get(opts, :sort, "date"))
    resume? = Keyword.get(opts, :resume, false)
    started_at = resume_started_at(resume?)
    Repo.transaction(fn -> insert_start_job!(page, sort, started_at, resume?) end)
  end

  defp insert_start_job!(page, sort, started_at, resume?) do
    args = %{
      "page" => page,
      "sort" => sort_string(sort),
      "started_at" => DateTime.to_iso8601(started_at)
    }

    case args |> McdbScrapeWorker.new() |> Oban.insert() do
      {:ok, job} ->
        unless job.conflict?, do: put_started_state(page, sort_string(sort), started_at, resume?)
        job

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  @doc """
  Fetches, applies, and records one list page, then chains the next page (or
  finishes the sweep). Called by `McdbScrapeWorker.perform/1`.

  The fetch happens outside any transaction — on a transient failure nothing
  is written and the caller (the worker) lets Oban retry the same page. On
  success, applying the page, updating the progress row, and chaining the
  next job all happen inside one `Repo.transaction/1` (`Oban.insert/1` joins
  it), so a retried page never double-counts and a committed page always has
  a successor.
  """
  @spec run_page(pos_integer(), sort(), DateTime.t()) :: :ok | {:error, term()}
  def run_page(page, sort, started_at) do
    case DecklistPages.fetch(page, sort) do
      {:ok, %{rows: rows, last_page: last_page}} ->
        page
        |> classify(rows, last_page)
        |> handle_page(page, sort, started_at, rows, last_page)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # An out-of-range page 200s with 0 rows; `last_page` is always the real
  # last page (the pagination link-text max), which can be *smaller* than the
  # requested page once we're past the end. `last_page` growing between pages
  # (new decklists published mid-sweep) is expected and handled by re-reading
  # it on every page rather than caching it.
  defp classify(page, rows, last_page) do
    cond do
      rows != [] and is_integer(last_page) and page >= last_page -> :last
      rows != [] and is_integer(last_page) -> :continue
      rows == [] and is_integer(last_page) and last_page < page -> :overshoot
      rows == [] -> {:error, {:empty_page, page, last_page}}
      true -> {:error, {:no_pagination, page}}
    end
  end

  defp handle_page(:last, page, sort, started_at, rows, last_page) do
    case Repo.transaction(fn -> apply_page(page, sort, rows, last_page) end) do
      {:ok, _} -> finish(started_at)
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_page(:continue, page, sort, started_at, rows, last_page) do
    case Repo.transaction(fn ->
           apply_page(page, sort, rows, last_page)
           enqueue_next!(page + 1, sort, started_at)
         end) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Pages shrank under us (decklists deleted/unlisted mid-sweep) — finish
  # without applying anything. The last successfully applied page stays
  # recorded; anything unseen shows up in the missing report.
  defp handle_page(:overshoot, _page, _sort, started_at, _rows, _last_page),
    do: finish(started_at)

  defp handle_page({:error, _} = error, _page, _sort, _started_at, _rows, _last_page), do: error

  defp apply_page(page, sort, rows, last_page) do
    applied = DecklistPages.apply_rows(rows)
    current = current_state_map()

    write_state(%{
      page: page,
      last_page: last_page,
      rows_seen: Map.get(current, :rows_seen, 0) + length(rows),
      matched: Map.get(current, :matched, 0) + applied.matched,
      unmatched: Map.get(current, :unmatched, 0) + applied.unmatched,
      users_updated: Map.get(current, :users_updated, 0) + applied.updated_users
    })

    Logger.info(
      "MCDB sweep page #{page}/#{last_page} (#{sort}): #{length(rows)} rows, " <>
        "#{applied.matched} matched, #{applied.updated_users} usernames"
    )

    applied
  end

  # `unique: false` — see the moduledoc on McdbScrapeWorker for why the chain
  # insert must not go through the worker's default uniqueness. The pattern
  # match makes an unexpected conflict crash the job (rolling back this
  # transaction) instead of silently ending the sweep after one page.
  defp enqueue_next!(page, sort, started_at) do
    args = %{
      "page" => page,
      "sort" => sort_string(sort),
      "started_at" => DateTime.to_iso8601(started_at)
    }

    %Oban.Job{conflict?: false} =
      args |> McdbScrapeWorker.new(unique: false, schedule_in: pace_seconds()) |> Oban.insert!()

    :ok
  end

  defp finish(started_at) do
    missing = missing_decklists(started_at)

    write_state(%{
      status: :done,
      finished_at: DateTime.utc_now(),
      missing_count: length(missing)
    })

    Logger.info("MCDB sweep done: #{length(missing)} decklists not seen")

    if missing != [] do
      Logger.info("MCDB sweep missing decklists: #{Enum.map_join(missing, ", ", & &1.mcdb_id)}")
    end

    :ok
  end

  @doc "Marks the sweep failed after its final attempt on `page`. Leaves `page` at the last applied page."
  @spec mark_failed(pos_integer(), term()) :: :ok
  def mark_failed(page, reason) do
    write_state(%{status: :failed, last_error: format_error(page, reason)})
    :ok
  end

  @doc "Records a transient failure without ending the sweep, so the admin page shows why it's backing off."
  @spec record_error(pos_integer(), term()) :: :ok
  def record_error(page, reason) do
    write_state(%{last_error: format_error(page, reason)})
    :ok
  end

  defp format_error(page, reason), do: "page #{page}: #{inspect(reason)}"

  @doc """
  Decklists this sweep (or the most recent completed one, keyed by
  `started_at`) never saw: local `:decklist` decks imported before the sweep
  started whose social sync timestamp predates it too.

  `inserted_at < started_at` excludes decks the hourly incremental sync
  imports *during* the sweep — those belong to the next sweep/refresh, not
  this report. `mcdb_social_synced_at < started_at` (rather than `is_nil`
  alone) makes re-runs correct, since earlier sweeps/manual runs may already
  have synced some of these decks.
  """
  @spec missing_decklists(DateTime.t()) :: [%{id: Ash.UUID.t(), mcdb_id: String.t()}]
  def missing_decklists(started_at) do
    # Only the `mcdb_social_synced_at` comparison needs second-precision
    # truncation (that column is `:utc_datetime`); truncating the
    # `inserted_at` bound too would floor it to the top of the second and
    # could wrongly exclude a deck inserted earlier in that same second.
    started_at_sec = DateTime.truncate(started_at, :second)

    Deck
    |> Ash.Query.filter(
      mcdb_type == :decklist and inserted_at < ^started_at and
        (is_nil(mcdb_social_synced_at) or mcdb_social_synced_at < ^started_at_sec)
    )
    |> Ash.Query.select([:id, :mcdb_id])
    |> Ash.Query.sort(mcdb_id: :asc)
    |> Ash.read!(authorize?: false)
    |> Enum.map(&%{id: &1.id, mcdb_id: &1.mcdb_id})
  end

  @doc """
  Username coverage, overall and restricted to authors of at least one
  `:decklist` deck (the "~100% done" criterion applies to that narrower set —
  authors of private `:deck`-only decks never appear on a list page, so they
  can never be filled by this sweep).
  """
  @spec username_coverage() :: %{
          total: non_neg_integer(),
          with_username: non_neg_integer(),
          decklist_authors: non_neg_integer(),
          decklist_authors_with_username: non_neg_integer()
        }
  def username_coverage do
    %{
      total: Ash.count!(McdbUser, authorize?: false),
      with_username: count_mcdb_users(&Ash.Query.filter(&1, not is_nil(username))),
      decklist_authors:
        count_mcdb_users(&Ash.Query.filter(&1, exists(decks, mcdb_type == :decklist))),
      decklist_authors_with_username:
        count_mcdb_users(
          &Ash.Query.filter(&1, not is_nil(username) and exists(decks, mcdb_type == :decklist))
        )
    }
  end

  defp count_mcdb_users(filter_fun) do
    McdbUser |> Ash.Query.new() |> filter_fun.() |> Ash.count!(authorize?: false)
  end

  @doc "Jittered delay (seconds) before the next chained page, from `:sanctum, Sanctum.Decks.McdbScrapeWorker, pace_seconds:`."
  @spec pace_seconds() :: non_neg_integer()
  def pace_seconds do
    range = Application.get_env(:sanctum, McdbScrapeWorker, [])[:pace_seconds] || 3..5
    Enum.random(range)
  end

  defp put_started_state(page, sort, started_at, resume?) do
    changes = %{
      status: :running,
      sort: sort,
      page: page - 1,
      started_at: started_at,
      finished_at: nil,
      last_error: nil,
      missing_count: nil
    }

    changes =
      if resume?,
        do: changes,
        else: Map.merge(changes, %{rows_seen: 0, matched: 0, unmatched: 0, users_updated: 0})

    write_state(changes)
  end

  defp resume_started_at(false), do: DateTime.utc_now()

  defp resume_started_at(true) do
    case current_state_map() do
      %{started_at: %DateTime{} = ts} -> ts
      _ -> DateTime.utc_now()
    end
  end

  defp current_state_map do
    case Decks.get_mcdb_scrape_state(authorize?: false) do
      {:ok, state} -> Map.take(state, @state_fields)
      _ -> %{}
    end
  end

  defp write_state(changes) do
    current_state_map()
    |> Map.merge(changes)
    |> then(&Decks.put_mcdb_scrape_state!(&1, authorize?: false))
  end

  defp to_sort_atom(sort) when sort in [:date, :likes], do: sort
  defp to_sort_atom("date"), do: :date
  defp to_sort_atom("likes"), do: :likes

  defp sort_string(:date), do: "date"
  defp sort_string(:likes), do: "likes"
end
