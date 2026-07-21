defmodule Sanctum.Homebrew.Maturity do
  @moduledoc """
  Creator-declared completeness of a homebrew project. Advisory metadata for
  discovery — it never gates functionality.
  """

  use Ash.Type.Enum, values: [:draft, :beta, :complete]
end
