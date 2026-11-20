defmodule Sanctum.Homebrew.SetReportStatus do
  @moduledoc """
  Where a `Sanctum.Homebrew.SetReport` stands in the admin queue: `:open`
  until an admin takes the set down (`:actioned`) or dismisses it.
  """

  use Ash.Type.Enum, values: [:open, :actioned, :dismissed]
end
