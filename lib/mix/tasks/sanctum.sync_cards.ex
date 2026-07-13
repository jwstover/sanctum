defmodule Mix.Tasks.Sanctum.SyncCards do
  @shortdoc "Syncs Marvel Champions cards and images from MarvelCDB"

  @moduledoc """
  Upserts the card catalog from MarvelCDB into the database and mirrors card
  scans into the public bucket.

      mix sanctum.sync_cards                  # all cards + images
      mix sanctum.sync_cards --pack core      # one pack (repeatable)
      mix sanctum.sync_cards --skip-images    # card data only
      mix sanctum.sync_cards --images-only    # bucket mirror only
      mix sanctum.sync_cards --dry-run        # report counts, write nothing
      mix sanctum.sync_cards --force          # re-upload existing objects

  Image mirroring needs `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
  `AWS_ENDPOINT_URL_S3`, and `BUCKET_NAME` in the environment. The bucket is
  shared between dev and prod, so images only ever need mirroring once; sync
  prod card data with:

      fly ssh console -a sanctum -C "/app/bin/sanctum eval 'Sanctum.Release.sync_cards()'"
  """

  use Mix.Task

  @requirements ["app.start"]

  @switches [
    all: :boolean,
    pack: :keep,
    images_only: :boolean,
    skip_images: :boolean,
    dry_run: :boolean,
    force: :boolean
  ]

  @impl true
  def run(argv) do
    {opts, _argv} = OptionParser.parse!(argv, strict: @switches)

    packs =
      case Keyword.get_values(opts, :pack) do
        [] -> :all
        packs -> packs
      end

    sync_opts = [
      packs: packs,
      data?: not Keyword.get(opts, :images_only, false),
      images?: not Keyword.get(opts, :skip_images, false),
      dry_run?: Keyword.get(opts, :dry_run, false),
      force?: Keyword.get(opts, :force, false)
    ]

    case Sanctum.CardSync.run(sync_opts) do
      {:ok, _summary} -> :ok
      {:error, %{}} -> Mix.raise("Card sync completed with failures (see output above)")
      {:error, reason} -> Mix.raise("Card sync failed: #{inspect(reason)}")
    end
  end
end
