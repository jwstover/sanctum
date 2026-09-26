defmodule Sanctum.Decks.McdbSocialRefresh do
  @moduledoc """
  Drives the daily MarvelCDB social refresh: keeps like counts and author
  usernames current for decks we already hold, at a cost of a few dozen
  requests a day.

  Walks the top `sort=likes` pages first, then the newest `sort=date` pages.
  `sort=date` alone would miss like-count changes on older popular decks;
  `sort=likes` alone would miss brand-new decks, which is what the date walk
  covers.

  The likes walk is capped at `likes_max_pages` rather than walked to the
  first all-zero page as a literal reading of the goal might suggest. A
  measurement against MarvelCDB on 2026-09-24 (`sort=likes`) found:

      page 1:    1980 .. 822 likes
      page 200:  all 12s
      page 800:  all 2s
      page 1200: all 1s
      page 1600: all 0s

  The first all-zero page sits somewhere between page 1200 and 1600 — walking
  there costs ~1,200-1,600 requests a day (1.5-2h at this module's pacing),
  which contradicts the "few dozen requests" goal. The deep pages are also
  blocks of *equal* like counts (every row tied at 12, then 2, then 1); inside
  a tie `sort=likes` has no stable order, so a deep walk would skip and repeat
  rows regardless. `likes_max_pages` (default 50, the top ~600 decks) is kept
  small and configurable; an all-zero page still stops the walk early as a
  secondary exit.

  Yields to the one-time backfill sweep (`Sanctum.Decks.McdbScrape`): if it's
  still running, `run/1` skips entirely rather than compete with it for the
  shared `:mcdb_scrape` queue slot and MarvelCDB's attention.
  """

  require Logger

  import Ecto.Query

  alias Sanctum.MarvelCdb.DecklistPages
  alias Sanctum.Repo

  @type sort :: :date | :likes

  # Named as a string (not aliased to the module) so this module has no
  # compile-time dependency on the backfill sweep's worker — the backfill
  # (#74) may not exist yet when this compiles. Keep in sync with
  # `Sanctum.Decks.McdbScrapeWorker`'s Oban worker name.
  @backfill_worker "Sanctum.Decks.McdbScrapeWorker"
  @backfill_incomplete_states ["available", "scheduled", "executing", "retryable"]

  @default_likes_max_pages 50
  @default_date_pages 35

  @doc """
  Runs the daily refresh: the top-liked pages, then the newest pages.

  Options (default from `Application.get_env(:sanctum, __MODULE__, [])`):

    * `:likes_max_pages` — cap on `sort=likes` pages walked (default #{@default_likes_max_pages}).
    * `:date_pages` — number of `sort=date` pages walked (default #{@default_date_pages}).
    * `:pace_fun` — 0-arity function called between pages (default sleeps).
    * `:backfill_running_fun` — 0-arity function used in place of `backfill_running?/0` (for tests).

  Returns `{:ok, summary}`, `{:skipped, :backfill_running}` if the backfill
  sweep is already running, or `{:error, {sort, page, reason}}` if a fetch
  fails outright. A fetch failure halts the whole run, but pages already
  applied before the failure are already persisted — a rerun is idempotent.
  """
  @spec run(keyword()) ::
          {:ok, map()} | {:skipped, :backfill_running} | {:error, {sort(), pos_integer(), term()}}
  def run(opts \\ []) do
    config = Application.get_env(:sanctum, __MODULE__, [])

    likes_max_pages =
      Keyword.get(opts, :likes_max_pages, config[:likes_max_pages] || @default_likes_max_pages)

    date_pages = Keyword.get(opts, :date_pages, config[:date_pages] || @default_date_pages)
    pace_fun = Keyword.get(opts, :pace_fun, &pace/0)
    backfill_running_fun = Keyword.get(opts, :backfill_running_fun, &backfill_running?/0)

    if backfill_running_fun.() do
      Logger.info("MCDB social refresh skipped: backfill sweep in progress")
      {:skipped, :backfill_running}
    else
      do_run(likes_max_pages, date_pages, pace_fun, backfill_running_fun)
    end
  end

  defp do_run(likes_max_pages, date_pages, pace_fun, backfill_running_fun) do
    with {:ok, likes} <-
           walk(:likes, likes_max_pages, pace_fun, backfill_running_fun, stop_on_all_zero: true),
         {:ok, date} <-
           maybe_walk_date(likes, :date, date_pages, pace_fun, backfill_running_fun) do
      summary = %{
        likes: Map.delete(likes, :stopped),
        date: Map.delete(date, :stopped),
        stopped: date.stopped
      }

      Logger.info("MCDB social refresh done: #{inspect(summary)}")
      {:ok, summary}
    end
  end

  # The likes walk can itself end because the backfill started mid-walk; in
  # that case skip the date walk too rather than layering a second signal.
  defp maybe_walk_date(
         %{stopped: :backfill_started} = likes,
         _sort,
         _max_pages,
         _pace_fun,
         _backfill_running_fun
       ) do
    {:ok, %{pages: 0, rows: 0, matched: 0, updated_users: 0, stopped: likes.stopped}}
  end

  defp maybe_walk_date(_likes, sort, max_pages, pace_fun, backfill_running_fun) do
    walk(sort, max_pages, pace_fun, backfill_running_fun, stop_on_all_zero: false)
  end

  @spec walk(sort(), non_neg_integer(), (-> any()), (-> boolean()), keyword()) ::
          {:ok, map()} | {:error, {sort(), pos_integer(), term()}}
  defp walk(sort, max_pages, pace_fun, backfill_running_fun, opts) do
    stop_on_all_zero = Keyword.fetch!(opts, :stop_on_all_zero)
    acc = %{pages: 0, rows: 0, matched: 0, updated_users: 0}

    1..max_pages
    |> Enum.reduce_while(acc, fn page, acc ->
      if page > 1, do: pace_fun.()

      if backfill_running_fun.() do
        {:halt, {:ok, Map.put(acc, :stopped, :backfill_started)}}
      else
        step_page(sort, page, acc, stop_on_all_zero)
      end
    end)
    |> case do
      %{} = acc -> {:ok, Map.put(acc, :stopped, :exhausted_pages)}
      {:ok, acc} -> {:ok, acc}
      {:error, {page, reason}} -> {:error, {sort, page, reason}}
    end
  end

  defp step_page(sort, page, acc, stop_on_all_zero) do
    case DecklistPages.fetch(page, sort) do
      {:error, reason} ->
        {:halt, {:error, {page, reason}}}

      {:ok, %{rows: [], last_page: _}} ->
        {:halt, {:ok, Map.put(acc, :stopped, :empty_page)}}

      {:ok, %{rows: rows, last_page: last_page}} ->
        applied = DecklistPages.apply_rows(rows)

        acc = %{
          pages: acc.pages + 1,
          rows: acc.rows + length(rows),
          matched: acc.matched + applied.matched,
          updated_users: acc.updated_users + applied.updated_users
        }

        Logger.info(
          "MCDB social refresh #{sort} page #{page}: #{length(rows)} rows, " <>
            "#{applied.matched} matched, #{applied.updated_users} usernames"
        )

        cond do
          stop_on_all_zero and Enum.all?(rows, &(&1.like_count == 0)) ->
            {:halt, {:ok, Map.put(acc, :stopped, :all_zero)}}

          is_integer(last_page) and page >= last_page ->
            {:halt, {:ok, Map.put(acc, :stopped, :last_page)}}

          true ->
            {:cont, acc}
        end
    end
  end

  @doc """
  Whether the one-time backfill sweep (`Sanctum.Decks.McdbScrape`) has an
  incomplete job. Checked via `oban_jobs` (not `McdbScrapeState.status`)
  because the backfill's chain always has a scheduled or executing successor
  while it's actually running; the state row can sit stale at `:running`
  after an admin cancel/discard, and may not exist yet at all. A `:failed`
  backfill waiting on a manual resume has no incomplete job, so the refresh
  correctly runs.
  """
  @spec backfill_running?() :: boolean()
  def backfill_running? do
    Repo.exists?(
      from j in Oban.Job,
        where: j.worker == ^@backfill_worker and j.state in ^@backfill_incomplete_states
    )
  end

  # Same pacing config as the backfill sweep, so the two never disagree on
  # how polite to be with MarvelCDB.
  defp pace do
    range =
      Application.get_env(:sanctum, Sanctum.Decks.McdbScrapeWorker, [])[:pace_seconds] || 3..5

    Process.sleep(:timer.seconds(Enum.random(range)))
  end
end
