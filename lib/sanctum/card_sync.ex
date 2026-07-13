defmodule Sanctum.CardSync do
  @moduledoc """
  Bulk-syncs the Marvel Champions card catalog from MarvelCDB.

  Card data upserts into Postgres via `Sanctum.MarvelCdb.sync_entries/2` with
  `image_url` pointing at the public bucket; scans are mirrored into that
  bucket once via `Sanctum.CardImages.mirror/2`. Everything is idempotent —
  re-running updates card data and skips images already in the bucket, so an
  interrupted run resumes by re-running.

  Entry points: `mix sanctum.sync_cards` (dev) and
  `Sanctum.Release.sync_cards/1` (prod, data only — the bucket is shared).
  """

  alias Sanctum.CardImages
  alias Sanctum.MarvelCdb

  # Pause between actual downloads from marvelcdb.com — the API asks
  # consumers to be polite. Skipped objects don't sleep.
  @download_pause_ms 200
  @progress_every 25

  @doc """
  Runs the sync. Options:

    * `:packs` — `:all` (default, one all-cards request) or a list of pack codes
    * `:data?` — upsert cards/sides (default true)
    * `:images?` — mirror scans to the bucket (default true; needs AWS env vars)
    * `:dry_run?` — report counts without writing (default false)
    * `:force?` — re-upload images that already exist (default false)

  Returns `{:ok, summary}`, `{:error, summary}` when any card or image failed
  (the run still processes everything), or `{:error, reason}` when the payload
  fetch itself failed.
  """
  def run(opts \\ []) do
    packs = Keyword.get(opts, :packs, :all)

    with {:ok, entries} <- fetch_entries(packs) do
      entries = Enum.uniq_by(entries, & &1["code"])

      if Keyword.get(opts, :dry_run?, false) do
        report_dry_run(entries)
      else
        run_sync(entries, opts)
      end
    end
  end

  defp run_sync(entries, opts) do
    data = if Keyword.get(opts, :data?, true), do: sync_data(entries)

    images =
      if Keyword.get(opts, :images?, true),
        do: sync_images(entries, Keyword.get(opts, :force?, false))

    summary = %{data: data, images: images}

    if failed?(summary), do: {:error, summary}, else: {:ok, summary}
  end

  defp fetch_entries(:all), do: MarvelCdb.get_all_cards()

  defp fetch_entries(packs) when is_list(packs) do
    Enum.reduce_while(packs, {:ok, []}, fn pack, {:ok, acc} ->
      case MarvelCdb.get_cards_by_pack(pack) do
        {:ok, cards} -> {:cont, {:ok, acc ++ cards}}
        err -> {:halt, err}
      end
    end)
  end

  defp sync_data(entries) do
    log("Syncing card data for #{length(entries)} entries...")

    {synced, failures} =
      MarvelCdb.sync_entries(entries, image_url_fun: &CardImages.public_url/1)

    Enum.each(failures, fn {base_code, error} ->
      log("  FAILED card #{base_code}: #{inspect(error)}")
    end)

    log("Card data: #{synced} cards synced, #{length(failures)} failed")
    %{synced: synced, failures: failures}
  end

  defp sync_images(entries, force?) do
    paths = image_paths(entries)
    total = length(paths)
    log("Mirroring #{total} images into #{CardImages.base_url()}...")

    {counts, failures} =
      paths
      |> Enum.with_index(1)
      |> Enum.reduce({%{uploaded: 0, skipped: 0}, []}, fn {path, index}, {counts, failures} ->
        result = CardImages.mirror(path, force: force?)

        if rem(index, @progress_every) == 0 or index == total do
          log("  #{index}/#{total} images processed")
        end

        case result do
          {:ok, :uploaded} ->
            Process.sleep(@download_pause_ms)
            {Map.update!(counts, :uploaded, &(&1 + 1)), failures}

          {:ok, _skipped_or_no_image} ->
            {Map.update!(counts, :skipped, &(&1 + 1)), failures}

          {:error, reason} ->
            {counts, [reason | failures]}
        end
      end)

    failures = Enum.reverse(failures)
    Enum.each(failures, &log("  FAILED image: #{inspect(&1)}"))

    log(
      "Images: #{counts.uploaded} uploaded, #{counts.skipped} skipped, #{length(failures)} failed"
    )

    Map.put(counts, :failures, failures)
  end

  # Every scan referenced by the payload: side images plus the parent-only
  # front/back files (e.g. 01097.png) that no side entry mentions directly.
  defp image_paths(entries) do
    entries
    |> Enum.flat_map(&[&1["imagesrc"], &1["backimagesrc"]])
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq_by(&CardImages.object_key/1)
  end

  defp report_dry_run(entries) do
    cards =
      entries
      |> Enum.map(&MarvelCdb.extract_base_code(&1["code"]))
      |> Enum.uniq()
      |> length()

    images = entries |> image_paths() |> length()

    log(
      "Dry run: #{length(entries)} entries -> #{cards} cards, #{images} images. Nothing written."
    )

    {:ok, :dry_run}
  end

  defp failed?(%{data: data, images: images}) do
    (data != nil and data.failures != []) or (images != nil and images.failures != [])
  end

  # Plain IO so progress shows for both `mix sanctum.sync_cards` and release eval.
  defp log(message), do: IO.puts(message)
end
