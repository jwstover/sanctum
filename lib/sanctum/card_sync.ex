defmodule Sanctum.CardSync do
  @moduledoc """
  Bulk-syncs the Marvel Champions card catalog from MarvelCDB.

  Card data upserts into Postgres via `Sanctum.MarvelCdb.sync_entries/2` with
  `image_url` pointing at the public bucket; scans are mirrored into that
  bucket once via `Sanctum.CardImages.mirror/2`. Everything is idempotent —
  re-running updates card data and skips images already in the bucket, so an
  interrupted run resumes by re-running.

  Entry points: `mix sanctum.sync_cards` (dev), `Sanctum.Release.sync_cards/1`
  (prod, data only — the bucket is shared), and `Sanctum.CardSync.Server` for
  the admin UI at `/cards/sync`.
  """

  alias Sanctum.CardImages
  alias Sanctum.MarvelCdb

  # Pause between actual downloads from marvelcdb.com — the API asks
  # consumers to be polite. Skipped objects don't sleep.
  @download_pause_ms 200

  @doc """
  Runs the sync. Options:

    * `:packs` — `:all` (default, one all-cards request) or a list of pack codes
    * `:data?` — upsert cards/sides (default true)
    * `:images?` — mirror scans to the bucket (default true; needs AWS env vars)
    * `:dry_run?` — report counts without writing (default false)
    * `:force?` — re-upload images that already exist (default false)
    * `:progress_fun` — receives progress events (see below); defaults to
      printing CLI-style progress to stdout

  Progress events: `{:data_started, %{entries, cards}}`,
  `{:card, %{index, total, base_code, name, ok?}}`, `{:data_done, %{synced,
  failures}}`, `{:images_started, %{total}}`, `{:image, %{index, total, file,
  result}}`, `{:images_done, %{uploaded, skipped, failures}}`, and
  `{:dry_run, %{entries, cards, images}}`.

  Returns `{:ok, summary}`, `{:error, summary}` when any card or image failed
  (the run still processes everything), or `{:error, reason}` when the payload
  fetch itself failed.
  """
  def run(opts \\ []) do
    packs = Keyword.get(opts, :packs, :all)
    progress = Keyword.get(opts, :progress_fun, &log_progress/1)

    with {:ok, entries} <- fetch_entries(packs) do
      entries = Enum.uniq_by(entries, & &1["code"])

      if Keyword.get(opts, :dry_run?, false) do
        report_dry_run(entries, progress)
      else
        run_sync(entries, opts, progress)
      end
    end
  end

  defp run_sync(entries, opts, progress) do
    data = if Keyword.get(opts, :data?, true), do: sync_data(entries, progress)

    images =
      if Keyword.get(opts, :images?, true),
        do: sync_images(entries, Keyword.get(opts, :force?, false), progress)

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

  defp sync_data(entries, progress) do
    progress.({:data_started, %{entries: length(entries), cards: card_count(entries)}})

    {synced, failures} =
      MarvelCdb.sync_entries(entries,
        image_url_fun: &CardImages.public_url/1,
        on_progress: &progress.({:card, &1})
      )

    progress.({:data_done, %{synced: synced, failures: failures}})
    %{synced: synced, failures: failures}
  end

  defp sync_images(entries, force?, progress) do
    paths = image_paths(entries)
    total = length(paths)
    progress.({:images_started, %{total: total}})

    {counts, failures} =
      paths
      |> Enum.with_index(1)
      |> Enum.reduce({%{uploaded: 0, skipped: 0}, []}, fn {path, index}, {counts, failures} ->
        result = CardImages.mirror(path, force: force?)

        progress.(
          {:image,
           %{index: index, total: total, file: Path.basename(path), result: image_outcome(result)}}
        )

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

    progress.(
      {:images_done, %{uploaded: counts.uploaded, skipped: counts.skipped, failures: failures}}
    )

    Map.put(counts, :failures, failures)
  end

  defp image_outcome({:ok, outcome}), do: outcome
  defp image_outcome({:error, _reason}), do: :error

  # Every scan referenced by the payload: side images plus the parent-only
  # front/back files (e.g. 01097.png) that no side entry mentions directly.
  defp image_paths(entries) do
    entries
    |> Enum.flat_map(&[&1["imagesrc"], &1["backimagesrc"]])
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq_by(&CardImages.object_key/1)
  end

  defp card_count(entries) do
    entries
    |> Enum.map(&MarvelCdb.extract_base_code(&1["code"]))
    |> Enum.uniq()
    |> length()
  end

  defp report_dry_run(entries, progress) do
    progress.(
      {:dry_run,
       %{
         entries: length(entries),
         cards: card_count(entries),
         images: entries |> image_paths() |> length()
       }}
    )

    {:ok, :dry_run}
  end

  defp failed?(%{data: data, images: images}) do
    (data != nil and data.failures != []) or (images != nil and images.failures != [])
  end

  # Default progress handler: CLI-style output for the mix task and release
  # eval. Plain IO so it shows in both contexts.
  defp log_progress({:data_started, %{entries: entries}}),
    do: IO.puts("Syncing card data for #{entries} entries...")

  defp log_progress({:data_done, %{synced: synced, failures: failures}}) do
    Enum.each(failures, fn {base_code, error} ->
      IO.puts("  FAILED card #{base_code}: #{inspect(error)}")
    end)

    IO.puts("Card data: #{synced} cards synced, #{length(failures)} failed")
  end

  defp log_progress({:images_started, %{total: total}}),
    do: IO.puts("Mirroring #{total} images into #{CardImages.base_url()}...")

  defp log_progress({:image, %{index: index, total: total}})
       when rem(index, 25) == 0 or index == total,
       do: IO.puts("  #{index}/#{total} images processed")

  defp log_progress({:images_done, %{uploaded: uploaded, skipped: skipped, failures: failures}}) do
    Enum.each(failures, &IO.puts("  FAILED image: #{inspect(&1)}"))
    IO.puts("Images: #{uploaded} uploaded, #{skipped} skipped, #{length(failures)} failed")
  end

  defp log_progress({:dry_run, %{entries: entries, cards: cards, images: images}}) do
    IO.puts("Dry run: #{entries} entries -> #{cards} cards, #{images} images. Nothing written.")
  end

  defp log_progress(_event), do: :ok
end
