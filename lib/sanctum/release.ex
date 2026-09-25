defmodule Sanctum.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :sanctum

  def migrate do
    load_app()

    for repo <- repos() do
      migrate_repo(repo)
    end
  end

  # Neon scales its compute to zero when the app is idle. On deploy this release
  # command runs on a fresh machine, and its first connection often lands before
  # the Neon endpoint has finished waking, so the initial migration attempt fails
  # with a connection/timeout error. Retry with a short backoff to give the
  # compute time to come online before aborting the deploy.
  defp migrate_repo(repo, attempts \\ 5) do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
  rescue
    error ->
      if attempts > 1 do
        IO.puts(
          "Migration attempt failed (#{Exception.message(error)}); " <>
            "the database may still be waking. Retrying in 3s (#{attempts - 1} left)..."
        )

        Process.sleep(3_000)
        migrate_repo(repo, attempts - 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Promotes a user to admin by email. The user must have signed in once.

      /app/bin/sanctum eval 'Sanctum.Release.promote_admin("me@example.com")'
  """
  def promote_admin(email) do
    {:ok, _} = Application.ensure_all_started(@app)

    email
    |> Sanctum.Accounts.get_user_by_email!(authorize?: false)
    |> Sanctum.Accounts.set_admin!(true, authorize?: false)
  end

  @doc """
  Syncs the card catalog from MarvelCDB. Defaults to card data only — images
  live in the shared public bucket and are mirrored from a dev machine with
  `mix sanctum.sync_cards`.

      /app/bin/sanctum eval 'Sanctum.Release.sync_cards()'
  """
  def sync_cards(opts \\ []) do
    # Unlike migrations, the sync needs the whole app (Repo, Ash) running.
    {:ok, _} = Application.ensure_all_started(@app)
    # Card sides carry an aspect FK to `aspects.key`, so the official rows must
    # exist before sync writes any. Idempotent; a no-op on an already-seeded DB
    # (the normal case) and the safety net for a fresh-environment rebuild.
    seed_aspects()
    Sanctum.CardSync.run(Keyword.merge([packs: :all, images?: false], opts))
  end

  @doc """
  One-time (idempotent) cleanup of stale duplicate canonical cards — reprints
  minted as full `Card`s with empty `CardSide`s before MarvelCDB duplicate
  handling collapsed them into `CardAlt`s (see
  `Sanctum.Games.DuplicateCardCleanup`). Defaults to a dry run that only reports;
  pass `dry_run: false` to commit.

      /app/bin/sanctum eval 'Sanctum.Release.cleanup_duplicate_cards()'
      /app/bin/sanctum eval 'Sanctum.Release.cleanup_duplicate_cards(dry_run: false)'
  """
  def cleanup_duplicate_cards(opts \\ []) do
    {:ok, _} = Application.ensure_all_started(@app)
    {:ok, report} = Sanctum.Games.DuplicateCardCleanup.run(opts)
    report
  end

  @doc """
  One-time backfill of MarvelCDB deck dates for decks imported before the
  fields were captured (see `Sanctum.Decks.McdbDateBackfill`). If it halts on
  a transient MarvelCDB failure, re-run with `since:` set to the reported day.

      /app/bin/sanctum eval 'Sanctum.Release.backfill_deck_dates()'
      /app/bin/sanctum eval 'Sanctum.Release.backfill_deck_dates(since: ~D[2024-01-15])'
  """
  def backfill_deck_dates(opts \\ []) do
    {:ok, _} = Application.ensure_all_started(@app)

    with {:ok, _summary} <- Sanctum.Decks.McdbDateBackfill.run(opts) do
      Sanctum.Decks.McdbDateBackfill.run_private()
    end
  end

  @doc """
  One-time backfill of `card_alts.pack_id` from the legacy `pack` code string
  for alts synced before the FK existed. New syncs populate it directly; alts
  whose pack code has no `Pack` row are left nil and simply don't count toward
  collection ownership.

      /app/bin/sanctum eval 'Sanctum.Release.backfill_alt_pack_ids()'
  """
  def backfill_alt_pack_ids do
    {:ok, _} = Application.ensure_all_started(@app)

    pack_ids =
      Map.new(Sanctum.Catalog.list_packs!(authorize?: false), &{&1.code, &1.id})

    require Ash.Query

    Sanctum.Games.CardAlt
    |> Ash.Query.filter(is_nil(pack_id) and not is_nil(pack))
    |> Ash.read!(authorize?: false)
    |> Enum.reduce(0, fn alt, count ->
      case pack_ids[alt.pack] do
        nil ->
          count

        pack_id ->
          Ash.update!(alt, %{pack_id: pack_id}, action: :update, authorize?: false)
          count + 1
      end
    end)
    |> then(&IO.puts("Backfilled pack_id on #{&1} card alts."))
  end

  @doc """
  Seeds the official player-card aspects (see `Sanctum.Games.Aspect`). Idempotent
  — existing rows are left untouched — so it is safe to run on every deploy.

      /app/bin/sanctum eval 'Sanctum.Release.seed_aspects()'
  """
  def seed_aspects do
    {:ok, _} = Application.ensure_all_started(@app)

    Enum.each(Sanctum.Games.Aspect.official(), fn attrs ->
      case Ash.get(Sanctum.Games.Aspect, attrs.key, authorize?: false) do
        {:ok, _existing} ->
          :ok

        _not_found ->
          Ash.create!(Sanctum.Games.Aspect, attrs, action: :create, authorize?: false)
      end
    end)
  end

  @doc """
  Starts (or resumes) the one-time MarvelCDB list-page sweep that fills deck
  authors' usernames and like counts (see `Sanctum.Decks.McdbScrape`). Runs
  in the `:mcdb_scrape` Oban queue; progress shows on `/admin`.

  Prefer the `/admin` "Start sweep" button over this function: `eval` boots a
  second VM on the same Fly machine, and `Application.ensure_all_started/1`
  starts the whole app, including `Sanctum.Oban.BootRescue` — which resets
  `executing` jobs whose `attempted_by` node matches this machine's, and
  could reset a sweep page the *live* app is genuinely still executing. This
  function is a fallback for when the app isn't reachable, and is only safe
  to run before a sweep has started (or while the running one is idle
  between pages).

      /app/bin/sanctum eval 'Sanctum.Release.start_mcdb_scrape()'
      /app/bin/sanctum eval 'Sanctum.Release.start_mcdb_scrape(page: 1200, resume: true)'
  """
  def start_mcdb_scrape(opts \\ []) do
    {:ok, _} = Application.ensure_all_started(@app)

    Sanctum.Decks.McdbScrape.start(opts)
  end

  @doc """
  Post-sweep report: username coverage plus the decklists the latest sweep
  didn't see (candidates for a follow-up reconcile). Same second-VM caveat as
  `start_mcdb_scrape/1` — harmless here since this only reads, but only run
  it after the sweep has actually finished (`state.status == :done`).

      /app/bin/sanctum eval 'IO.inspect(Sanctum.Release.mcdb_scrape_report(), limit: :infinity)'
  """
  def mcdb_scrape_report do
    {:ok, _} = Application.ensure_all_started(@app)

    case Sanctum.Decks.get_mcdb_scrape_state(authorize?: false) do
      {:ok, %{started_at: %DateTime{} = started_at} = state} ->
        %{
          state: state,
          coverage: Sanctum.Decks.McdbScrape.username_coverage(),
          missing: Sanctum.Decks.McdbScrape.missing_decklists(started_at)
        }

      _ ->
        {:error, :never_run}
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
