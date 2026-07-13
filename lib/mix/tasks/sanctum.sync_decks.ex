defmodule Mix.Tasks.Sanctum.SyncDecks do
  @shortdoc "Syncs published decklists from MarvelCDB"

  @moduledoc """
  Imports MarvelCDB's published decklists into the database, walking each day
  from the stored cursor (or `--since`) through today. Idempotent — re-running
  upserts.

      mix sanctum.sync_decks                    # resume from cursor -> today
      mix sanctum.sync_decks --since 2024-01-15 # from a specific date
      mix sanctum.sync_decks --until 2024-01-20 # stop at a specific date

  Use `--since` with an early date for a one-time historical backfill
  (~2,500 days from MarvelCDB's launch, ~8 min at the built-in pacing).
  """

  use Mix.Task

  @requirements ["app.start"]

  @switches [
    since: :string,
    until: :string
  ]

  @impl true
  def run(argv) do
    {opts, _argv} = OptionParser.parse!(argv, strict: @switches)

    sync_opts =
      []
      |> maybe_put_date(:since, opts[:since])
      |> maybe_put_date(:until, opts[:until])

    {:ok, _summary} = Sanctum.DeckSync.run(sync_opts)
    :ok
  end

  defp maybe_put_date(opts, _key, nil), do: opts

  defp maybe_put_date(opts, key, value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> Keyword.put(opts, key, date)
      {:error, _} -> Mix.raise("Invalid #{key} date: #{value} (expected YYYY-MM-DD)")
    end
  end
end
