defmodule Sanctum.Games.CardOrigin do
  @moduledoc """
  Where a card comes from: the official MarvelCDB-synced catalog, or a
  user-created homebrew project (`Sanctum.Homebrew`).
  """

  use Ash.Type.Enum, values: [:official, :custom]
end
