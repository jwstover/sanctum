defmodule Mix.Tasks.Sanctum.BackfillDeckDates do
  @shortdoc "Backfills MarvelCDB dates onto already-imported decks"

  @moduledoc """
  One-time backfill of `mcdb_date_creation`/`mcdb_date_update` for decks
  imported before those fields were captured. Walks MarvelCDB's `by_date`
  endpoint and copies just the two dates onto existing rows — it does not
  re-import decks. Idempotent: only rows still missing the dates are touched.

      mix sanctum.backfill_deck_dates                    # full walk (2019 -> today)
      mix sanctum.backfill_deck_dates --since 2024-01-15 # resume after a halt
      mix sanctum.backfill_deck_dates --until 2024-01-20 # stop at a specific date
      mix sanctum.backfill_deck_dates --private          # also re-import URL decks

  `--private` additionally re-imports `mcdb_type: :deck` rows (private decks
  imported by URL), which the by-date walk can't reach.
  """

  use Mix.Task

  @requirements ["app.start"]

  @switches [
    since: :string,
    until: :string,
    private: :boolean
  ]

  @impl true
  def run(argv) do
    {opts, _argv} = OptionParser.parse!(argv, strict: @switches)

    backfill_opts = Mix.Tasks.Sanctum.DateOpts.build(opts, [:since, :until])

    case Sanctum.Decks.McdbDateBackfill.run(backfill_opts) do
      {:ok, _summary} ->
        if opts[:private], do: Sanctum.Decks.McdbDateBackfill.run_private()
        :ok

      {:error, summary} ->
        Mix.raise(
          "Date backfill halted at #{summary.halted.date}: #{inspect(summary.halted.reason)} " <>
            "(#{summary.updated} updated before halting). " <>
            "Re-run with --since #{summary.halted.date} to resume."
        )
    end
  end
end
