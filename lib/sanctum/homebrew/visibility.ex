defmodule Sanctum.Homebrew.Visibility do
  @moduledoc """
  Who can see a homebrew project and its cards.

  `:private` and `:unlisted` are creator-only for now — unlisted share links
  land with the public directory phase as a dedicated read action, so the
  global read filter never has to loosen.
  """

  use Ash.Type.Enum, values: [:private, :unlisted, :published]
end
