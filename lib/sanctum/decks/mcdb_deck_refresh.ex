defmodule Sanctum.Decks.McdbDeckRefresh do
  @moduledoc """
  Adaptive per-decklist refresh of MarvelCDB like counts.

  `Sanctum.Decks.McdbSocialRefresh`'s capped `sort=likes` walk (top ~600 decks)
  plus its newest-35-pages date walk leave a coverage gap: a decklist that
  gains a few likes, never cracks the top ~600 and has aged out of the date
  window would never be refreshed. This module closes it: every locally-known
  decklist carries its own schedule and is re-fetched from its own detail page
  (`/decklist/view/{id}`) when due. It runs alongside the list walks.

  ## Schedule

  `mcdb_like_changed_at` is the last time we saw the like count change (seeded
  from `mcdb_date_creation`). After each check:

      next_check_at = checked_at + clamp(growth_factor * (checked_at - changed_at), floor, ceiling)

  A changed count resets the interval to the floor; a quiet deck's interval
  grows ~(1 + growth_factor)x per check (3d, 9d, 27d, 81d ... after its last
  change with the defaults) until the ceiling. No interval is stored — it's a
  function of two timestamps.

  ## Defaults (⚠️ Decision to confirm — sized, not measured)

  `floor_days: 3`, `growth_factor: 2.0`, `ceiling_days: 365`,
  `initial_delay_days: 7` (a new deck's first check, about when it leaves the
  date walk's window), `batch_size: 25` per hourly run, a hard cap of 600
  requests/day. Sizing against ~55k decklists (2026-09-30): tail at the ceiling
  ~120/day, new-deck warm-up ~220/day, change-driven ~4/day per detected change
  (X changes/day), so ~340 + 4X requests/day, plus the walks' 85. Rollout is
  spread by jittered seeding (~235/day), so there is no thundering herd. If the
  due backlog (logged each run) grows across days, tune the cap or constants;
  decks then slip later but are never skipped.

  ## Why the schedule lives on the row, not in per-deck Oban jobs

    * `McdbScrapeWorker` relies on at most one MarvelCDB fetch in flight
      cluster-wide; the `:mcdb_scrape` queue `limit: 1` only holds per node.
      One unique batch job keeps that property.
    * A batch job can sleep between fetches (same `pace_seconds` as the other
      scrapers); per-deck jobs would run back to back.
    * Seeding is one bulk UPDATE rather than ~55k job inserts, and `oban_jobs`
      isn't loaded with 55k long-lived `scheduled` rows.

  Every run also seeds decklists with no schedule yet, so decks imported by any
  path get scheduled within an hour without touching import code.
  """

  require Logger
  require Ash.Query

  import Ecto.Query

  alias Sanctum.Decks
  alias Sanctum.Decks.Deck
  alias Sanctum.Decks.McdbSocialRefresh
  alias Sanctum.MarvelCdb.DecklistPages
  alias Sanctum.Repo

  @social_refresh_worker "Sanctum.Decks.McdbSocialRefreshWorker"
  @max_parse_failures 3

  @defaults [
    floor_days: 3,
    ceiling_days: 365,
    growth_factor: 2.0,
    initial_delay_days: 7,
    batch_size: 25
  ]

  @doc """
  Seeds unscheduled decklists, then fetches up to `batch_size` of the
  oldest-due decks' detail pages and reschedules each.

  Options (defaults from `Application.get_env(:sanctum, #{inspect(__MODULE__)}, [])`):
  `:floor_days`, `:ceiling_days`, `:growth_factor`, `:initial_delay_days`,
  `:batch_size`, plus `:pace_fun`, `:backfill_running_fun` and `:now` (tests).

  Returns `{:ok, summary}`, `{:skipped, reason}`, or `{:error, reason}` when a
  fetch fails outright (the failing deck's schedule is left untouched so it is
  retried first; earlier decks are already persisted) or the markup appears to
  have changed (#{@max_parse_failures} parse failures in one run).
  """
  @spec run(keyword()) :: {:ok, map()} | {:skipped, atom()} | {:error, term()}
  def run(opts \\ []) do
    config = config(opts)
    pace_fun = Keyword.get(opts, :pace_fun, &pace/0)

    backfill_running_fun =
      Keyword.get(opts, :backfill_running_fun, &McdbSocialRefresh.backfill_running?/0)

    cond do
      backfill_running_fun.() ->
        Logger.info("MCDB deck refresh skipped: backfill sweep in progress")
        {:skipped, :backfill_running}

      social_refresh_running?() ->
        Logger.info("MCDB deck refresh skipped: social refresh in progress")
        {:skipped, :social_refresh_running}

      true ->
        now =
          Keyword.get_lazy(opts, :now, fn -> DateTime.truncate(DateTime.utc_now(), :second) end)

        do_run(config, now, pace_fun)
    end
  end

  @doc """
  When to next check a deck: `growth_factor` times the time since its like
  count last changed, clamped to `[floor_days, ceiling_days]`.
  """
  @spec next_check_at(DateTime.t(), DateTime.t(), keyword()) :: DateTime.t()
  def next_check_at(checked_at, changed_at, config) do
    floor = config[:floor_days] * 86_400
    ceiling = config[:ceiling_days] * 86_400
    quiet = DateTime.diff(checked_at, changed_at)
    seconds = (config[:growth_factor] * quiet) |> round() |> max(floor) |> min(ceiling)

    checked_at |> DateTime.add(seconds, :second) |> DateTime.truncate(:second)
  end

  defp config(opts) do
    app = Application.get_env(:sanctum, __MODULE__, [])

    Enum.map(@defaults, fn {key, default} ->
      {key, Keyword.get(opts, key, Keyword.get(app, key, default))}
    end)
  end

  defp do_run(config, now, pace_fun) do
    seed_unscheduled(config)

    due =
      Deck
      |> Ash.Query.filter(mcdb_type == :decklist and mcdb_social_next_check_at <= ^now)
      |> Ash.count!(authorize?: false)

    batch =
      Deck
      |> Ash.Query.filter(mcdb_type == :decklist and mcdb_social_next_check_at <= ^now)
      |> Ash.Query.sort(mcdb_social_next_check_at: :asc)
      |> Ash.Query.limit(config[:batch_size])
      |> Ash.Query.select([
        :id,
        :mcdb_id,
        :mcdb_like_count,
        :mcdb_like_changed_at,
        :mcdb_social_next_check_at,
        :updated_at
      ])
      |> Ash.read!(authorize?: false)

    acc = %{checked: 0, changed: 0, not_found: 0, parse_failures: 0}

    batch
    |> Enum.with_index()
    |> Enum.reduce_while(acc, fn {deck, index}, acc ->
      if index > 0, do: pace_fun.()
      check_deck(deck, now, config, acc)
    end)
    |> finish(due, config)
  end

  defp finish({:error, _} = error, due, _config) do
    Logger.warning("MCDB deck refresh halted with #{due} due: #{inspect(error)}")
    error
  end

  defp finish(acc, due, _config) do
    processed = acc.checked + acc.not_found + acc.parse_failures

    Logger.info(
      "MCDB deck refresh: #{due} due, #{acc.checked} checked, #{acc.changed} changed, " <>
        "#{acc.not_found} not found, #{acc.parse_failures} parse failures"
    )

    {:ok, Map.merge(acc, %{due: due, backlog: due - processed})}
  end

  defp check_deck(deck, now, config, acc) do
    case DecklistPages.fetch_detail(deck.mcdb_id) do
      {:ok, %{like_count: count}} ->
        changed? = count != deck.mcdb_like_count
        changed_at = if changed?, do: now, else: deck.mcdb_like_changed_at || now

        Decks.set_deck_mcdb_social!(
          deck,
          %{
            mcdb_like_count: count,
            mcdb_social_synced_at: now,
            next_check_at: next_check_at(now, changed_at, config)
          },
          authorize?: false
        )

        {:cont,
         %{acc | checked: acc.checked + 1, changed: acc.changed + if(changed?, do: 1, else: 0)}}

      {:error, :not_found} ->
        # Deleted or unpublished on MarvelCDB: leave the counts, check rarely.
        Logger.info("MCDB deck refresh: decklist #{deck.mcdb_id} not found")
        reschedule(deck, DateTime.add(now, config[:ceiling_days] * 86_400, :second))
        {:cont, %{acc | not_found: acc.not_found + 1}}

      {:error, :no_social_counts} ->
        Logger.warning("MCDB deck refresh: no social counts on decklist #{deck.mcdb_id}")
        reschedule(deck, DateTime.add(now, config[:floor_days] * 86_400, :second))
        failures = acc.parse_failures + 1

        if failures >= @max_parse_failures do
          {:halt, {:error, {:parse_failures, failures}}}
        else
          {:cont, %{acc | parse_failures: failures}}
        end

      {:error, reason} ->
        # Schedule untouched: the deck stays oldest-due and is retried first.
        {:halt, {:error, {deck.mcdb_id, reason}}}
    end
  end

  defp reschedule(deck, next) do
    Decks.set_deck_mcdb_social!(deck, %{next_check_at: next}, authorize?: false)
  end

  # Schedules decklists that have no schedule yet, in one statement. A deck
  # younger than `initial_delay_days` is first checked at creation + that
  # delay; an older one gets `now + random() * min(growth * age, ceiling)`,
  # so ~55k existing decks don't all fall due at once.
  #
  # Raw `update_all` rather than an Ash bulk action: the Deck resource's global
  # ValidateHero change can't run atomically, and `update_all` also leaves
  # `updated_at` alone, which the deck browser's recency sort depends on.
  defp seed_unscheduled(config) do
    from(d in "decks",
      where: d.mcdb_type == "decklist" and is_nil(d.mcdb_social_next_check_at),
      update: [
        set: [
          mcdb_like_changed_at:
            fragment(
              "COALESCE(?, ?, ?)",
              d.mcdb_like_changed_at,
              d.mcdb_date_creation,
              d.inserted_at
            ),
          mcdb_social_next_check_at:
            fragment(
              """
              CASE WHEN now() - COALESCE(?, ?) < make_interval(days => ?)
              THEN COALESCE(?, ?) + make_interval(days => ?)
              ELSE now() + random() * LEAST(? * (now() - COALESCE(?, ?)), make_interval(days => ?)) END
              """,
              d.mcdb_date_creation,
              d.inserted_at,
              ^config[:initial_delay_days],
              d.mcdb_date_creation,
              d.inserted_at,
              ^config[:initial_delay_days],
              ^(config[:growth_factor] * 1.0),
              d.mcdb_date_creation,
              d.inserted_at,
              ^config[:ceiling_days]
            )
        ]
      ]
    )
    |> Repo.update_all([])
  end

  # The queue limit is per node, so also check `oban_jobs` for an executing
  # social refresh (which may be running on another node).
  defp social_refresh_running? do
    Repo.exists?(
      from j in Oban.Job, where: j.worker == ^@social_refresh_worker and j.state == "executing"
    )
  end

  defp pace do
    range =
      Application.get_env(:sanctum, Sanctum.Decks.McdbScrapeWorker, [])[:pace_seconds] || 3..5

    Process.sleep(:timer.seconds(Enum.random(range)))
  end
end
