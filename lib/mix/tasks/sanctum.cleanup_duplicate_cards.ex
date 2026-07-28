defmodule Mix.Tasks.Sanctum.CleanupDuplicateCards do
  @shortdoc "Removes stale duplicate canonical cards that should be alts"

  @moduledoc """
  One-time (idempotent) cleanup of stale *duplicate* canonical cards — reprints
  that were minted as full `Card`s (with empty `CardSide`s that pollute the pool)
  before MarvelCDB duplicate handling collapsed reprints into thin `CardAlt`s.

  See `Sanctum.Games.DuplicateCardCleanup` for the full explanation. Deck slots
  pointing at the stale cards are re-pointed (and quantities merged) onto the real
  canonical card before the stale cards are deleted.

      mix sanctum.cleanup_duplicate_cards            # dry run: report only, no writes
      mix sanctum.cleanup_duplicate_cards --apply    # commit the cleanup
  """

  use Mix.Task

  @requirements ["app.start"]

  @switches [apply: :boolean]

  @impl true
  def run(argv) do
    {opts, _argv} = OptionParser.parse!(argv, strict: @switches)
    apply? = opts[:apply] || false

    {:ok, report} = Sanctum.Games.DuplicateCardCleanup.run(dry_run: not apply?)

    mode = if report.dry_run, do: "DRY RUN (no changes written)", else: "APPLIED"

    Mix.shell().info("""

    Duplicate card cleanup — #{mode}
      stale duplicate cards:      #{report.stale_cards}
      stale deck slots removed:   #{report.deck_rows_removed}
      merged into new deck rows:  #{report.canonical_rows_created}
      merged into existing rows:  #{report.canonical_rows_updated}
      alts re-pointed:            #{report.alts_repointed}
    """)

    if report.dry_run and report.stale_cards > 0 do
      Mix.shell().info("Re-run with --apply to commit these changes.")
    end
  end
end
