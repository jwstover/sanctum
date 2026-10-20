defmodule Sanctum.Decks.McdbSocialRefresh do
  @moduledoc """
  Drives the daily MarvelCDB social refresh. It does two cheap things:

    * **Recent like counts.** For each day in the last `recent_like_days`
      (excluding today, which the hourly sync covers), fetch `by_date` and
      write `like_count` onto decks we already hold. This closes the gap
      between the hourly sync (which only re-imports today and yesterday) and
      `Sanctum.Decks.McdbDeckRefresh`'s first check at creation +
      `initial_delay_days`. About 7 API requests a day.
    * **Author usernames.** The API returns only a `user_id`, so usernames
      still come from the HTML list pages. The walk is driven by a pending set:
      authors with no username who have a `:decklist` deck created within
      `username_lookback_days`. With nothing pending, no list page is
      requested; otherwise `sort=date` pages are walked from page 1 until every
      pending author has been filled (or the page cap is hit). The lookback
      keeps authors who can never be filled (private `:deck`-only authors,
      unlisted decks) from pinning every run at the cap.

  The old `sort=likes` walk is gone: the decklist API carries `like_count`,
  and the long tail is covered by `McdbDeckRefresh`.

  Scraping stays out of the hourly sync path on purpose. `DecklistSyncWorker`
  runs on `:default`, so scraping there would break the "at most one
  MarvelCDB fetch in flight" invariant the `:mcdb_scrape` queue provides, and
  would couple the API sync to HTML scraping. (A future Ash Signal on
  `McdbUser` creation with a nil username is the natural trigger.)

  Yields to the one-time backfill sweep (`Sanctum.Decks.McdbScrape`): if it's
  still running, `run/1` skips entirely rather than compete with it for the
  shared `:mcdb_scrape` queue slot and MarvelCDB's attention.
  """

  require Ash.Query
  require Logger

  import Ecto.Query

  alias Sanctum.Decks
  alias Sanctum.Decks.Deck
  alias Sanctum.Decks.McdbUser
  alias Sanctum.MarvelCdb
  alias Sanctum.MarvelCdb.DecklistPages
  alias Sanctum.Repo

  # Named as a string (not aliased to the module) so this module has no
  # compile-time dependency on the backfill sweep's worker — the backfill
  # (#74) may not exist yet when this compiles. Keep in sync with
  # `Sanctum.Decks.McdbScrapeWorker`'s Oban worker name.
  @backfill_worker "Sanctum.Decks.McdbScrapeWorker"
  @backfill_incomplete_states ["available", "scheduled", "executing", "retryable"]

  @default_username_lookback_days 14
  @default_username_max_pages 35

  @type run_error ::
          {:recent_likes, Date.t(), term()} | {:usernames, pos_integer(), term()}

  @doc """
  Runs the daily refresh: recent like counts, then the username walk.

  Options (default from `Application.get_env(:sanctum, __MODULE__, [])`):

    * `:recent_like_days` — `by_date` days to refresh, ending yesterday
      (default `McdbDeckRefresh`'s `initial_delay_days`, else 7).
    * `:username_lookback_days` — how recent a deck must be for its author to
      count as pending (default #{@default_username_lookback_days}).
    * `:username_max_pages` — safety cap on `sort=date` pages (default #{@default_username_max_pages}).
    * `:today` — a `Date`, for tests (default `Date.utc_today/0`).
    * `:pace_fun` — 0-arity function called between requests (default sleeps).
    * `:backfill_running_fun` — 0-arity function used in place of `backfill_running?/0` (for tests).

  Returns `{:ok, summary}`, `{:skipped, :backfill_running}` if the backfill
  sweep is already running, or `{:error, {:recent_likes, date, reason}}` /
  `{:error, {:usernames, page, reason}}` if a fetch fails outright. A failure
  halts the whole run, but work applied before it is already persisted — a
  rerun is idempotent.
  """
  @spec run(keyword()) ::
          {:ok, map()} | {:skipped, :backfill_running} | {:error, run_error()}
  def run(opts \\ []) do
    config = Application.get_env(:sanctum, __MODULE__, [])

    recent_like_days =
      Keyword.get(
        opts,
        :recent_like_days,
        config[:recent_like_days] || default_recent_like_days()
      )

    lookback_days =
      Keyword.get(
        opts,
        :username_lookback_days,
        config[:username_lookback_days] || @default_username_lookback_days
      )

    max_pages =
      Keyword.get(
        opts,
        :username_max_pages,
        config[:username_max_pages] || @default_username_max_pages
      )

    today = Keyword.get(opts, :today, Date.utc_today())
    pace_fun = Keyword.get(opts, :pace_fun, &pace/0)
    backfill_running_fun = Keyword.get(opts, :backfill_running_fun, &backfill_running?/0)

    if backfill_running_fun.() do
      Logger.info("MCDB social refresh skipped: backfill sweep in progress")
      {:skipped, :backfill_running}
    else
      with {:ok, likes} <- refresh_recent_likes(recent_like_days, today, pace_fun),
           {:ok, usernames} <-
             fill_usernames(lookback_days, max_pages, today, pace_fun, backfill_running_fun) do
        summary = %{recent_likes: likes, usernames: usernames}
        Logger.info("MCDB social refresh done: #{inspect(summary)}")
        {:ok, summary}
      end
    end
  end

  # Tied to McdbDeckRefresh's first check so the two windows can't drift apart.
  defp default_recent_like_days do
    Application.get_env(:sanctum, Sanctum.Decks.McdbDeckRefresh, [])[:initial_delay_days] || 7
  end

  ## Recent like counts

  defp refresh_recent_likes(days, _today, _pace_fun) when days <= 0 do
    {:ok, %{days: 0, decklists: 0, matched: 0, missing_like_count: 0}}
  end

  defp refresh_recent_likes(days, today, pace_fun) do
    acc = %{days: 0, decklists: 0, matched: 0, missing_like_count: 0}

    Date.range(Date.add(today, -days), Date.add(today, -1))
    |> Enum.reduce_while(acc, fn date, acc ->
      if acc.days > 0, do: pace_fun.()

      case fetch_day(date) do
        {:ok, decklists} ->
          applied = apply_like_counts(decklists)

          Logger.info(
            "MCDB social refresh #{date}: #{length(decklists)} decklists, " <>
              "#{applied.matched} matched, #{applied.missing_like_count} without like_count"
          )

          {:cont,
           %{
             days: acc.days + 1,
             decklists: acc.decklists + length(decklists),
             matched: acc.matched + applied.matched,
             missing_like_count: acc.missing_like_count + applied.missing_like_count
           }}

        {:error, reason} ->
          {:halt, {:error, {:recent_likes, date, reason}}}
      end
    end)
    |> case do
      {:error, _} = error ->
        error

      acc ->
        if acc.missing_like_count > 0 do
          Logger.warning(
            "MCDB social refresh: #{acc.missing_like_count} decklists came back without like_count"
          )
        end

        {:ok, acc}
    end
  end

  # Same empty-day-500 disambiguation as `DeckSync.sync_date/1`: MarvelCDB
  # 500s on days with no decklists, so only a failing canary is a real outage.
  defp fetch_day(date) do
    case MarvelCdb.get_decklists_by_date(date) do
      {:ok, decklists} ->
        {:ok, decklists}

      {:error, :not_found} ->
        {:ok, []}

      {:error, {:server_error, _status}} = error ->
        if MarvelCdb.decklists_endpoint_healthy?(), do: {:ok, []}, else: error

      {:error, _} = error ->
        error
    end
  end

  # Writes only `like_count`, only onto decks we already hold; the hourly sync
  # imports the rest. A payload without an integer `like_count` is skipped,
  # never read as 0.
  defp apply_like_counts(decklists) do
    counts = Map.new(decklists, &{to_string(&1["id"]), &1["like_count"]})
    ids = Map.keys(counts)

    decks =
      Deck
      |> Ash.Query.filter(mcdb_type == :decklist and mcdb_id in ^ids)
      |> Ash.Query.select([:id, :mcdb_id, :mcdb_like_count, :updated_at])
      |> Ash.read!(authorize?: false)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    missing =
      Enum.count(decks, fn deck ->
        case Map.fetch!(counts, deck.mcdb_id) do
          count when is_integer(count) ->
            Decks.set_deck_mcdb_social!(
              deck,
              %{mcdb_like_count: count, mcdb_social_synced_at: now},
              authorize?: false
            )

            false

          _ ->
            true
        end
      end)

    %{matched: length(decks), missing_like_count: missing}
  end

  ## Usernames

  defp fill_usernames(lookback_days, max_pages, today, pace_fun, backfill_running_fun) do
    pending = pending_user_ids(lookback_days, today)
    initial = MapSet.size(pending)

    if initial == 0 do
      {:ok,
       %{
         pending: 0,
         pages: 0,
         rows: 0,
         matched: 0,
         updated_users: 0,
         remaining: 0,
         stopped: :nothing_pending
       }}
    else
      walk_pages(initial, pending, max_pages, pace_fun, backfill_running_fun)
    end
  end

  defp walk_pages(initial, pending, max_pages, pace_fun, backfill_running_fun) do
    acc = %{pending: initial, pages: 0, rows: 0, matched: 0, updated_users: 0}

    1..max_pages//1
    |> Enum.reduce_while({acc, pending}, fn page, {acc, pending} ->
      if page > 1, do: pace_fun.()

      if backfill_running_fun.() do
        {:halt, {:ok, acc, pending, :backfill_started}}
      else
        step_page(page, acc, pending)
      end
    end)
    |> case do
      {:ok, acc, pending, stopped} -> finish_usernames(acc, pending, stopped)
      {:error, _} = error -> error
      {acc, pending} -> finish_usernames(acc, pending, :exhausted_pages)
    end
  end

  defp step_page(page, acc, pending) do
    case DecklistPages.fetch(page, :date) do
      {:error, reason} ->
        {:halt, {:error, {:usernames, page, reason}}}

      {:ok, %{rows: []}} ->
        {:halt, {:ok, acc, pending, :empty_page}}

      {:ok, %{rows: rows, last_page: last_page}} ->
        applied = DecklistPages.apply_rows(rows)
        pending = MapSet.difference(pending, MapSet.new(applied.user_ids))

        acc = %{
          acc
          | pages: acc.pages + 1,
            rows: acc.rows + length(rows),
            matched: acc.matched + applied.matched,
            updated_users: acc.updated_users + applied.updated_users
        }

        Logger.info(
          "MCDB social refresh date page #{page}: #{length(rows)} rows, " <>
            "#{applied.matched} matched, #{applied.updated_users} usernames, " <>
            "#{MapSet.size(pending)} pending"
        )

        cond do
          MapSet.size(pending) == 0 -> {:halt, {:ok, acc, pending, :all_known}}
          is_integer(last_page) and page >= last_page -> {:halt, {:ok, acc, pending, :last_page}}
          true -> {:cont, {acc, pending}}
        end
    end
  end

  defp finish_usernames(acc, pending, stopped) do
    if stopped == :exhausted_pages and MapSet.size(pending) > 0 do
      Logger.warning(
        "MCDB social refresh: hit the page cap with #{MapSet.size(pending)} authors still without a username"
      )
    end

    {:ok, Map.merge(acc, %{remaining: MapSet.size(pending), stopped: stopped})}
  end

  defp pending_user_ids(lookback_days, today) do
    cutoff = DateTime.new!(Date.add(today, -lookback_days), ~T[00:00:00], "Etc/UTC")

    McdbUser
    |> Ash.Query.filter(
      is_nil(username) and
        exists(decks, mcdb_type == :decklist and mcdb_date_creation >= ^cutoff)
    )
    |> Ash.Query.select([:mcdb_user_id])
    |> Ash.read!(authorize?: false)
    |> MapSet.new(& &1.mcdb_user_id)
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
