defmodule Sanctum.Decks.DateWalkLog do
  @moduledoc """
  Shared Logger output for the MarvelCDB by-date walk jobs (`Sanctum.DeckSync`,
  `Sanctum.Decks.McdbDateBackfill`), which emit the same progress-event shapes.
  Job-specific events keep their own clauses in each job's `log_progress/1`.
  """

  require Logger

  @doc "Logs the `{:started, ...}` walk event; `verb` names the job."
  def started(verb, %{from: from, to: to, days: days}),
    do: Logger.info("#{verb} from #{from} to #{to} (#{days} days)...")

  @doc "Logs the `{:date_error, ...}` walk event."
  def date_error(%{date: date, reason: reason}),
    do: Logger.warning("  #{date}: fetch failed: #{inspect(reason)}")
end
