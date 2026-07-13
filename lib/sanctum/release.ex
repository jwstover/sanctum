defmodule Sanctum.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :sanctum

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
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

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
