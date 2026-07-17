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
    Sanctum.CardSync.run(Keyword.merge([packs: :all, images?: false], opts))
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

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
