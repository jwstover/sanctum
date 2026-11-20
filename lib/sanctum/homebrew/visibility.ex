defmodule Sanctum.Homebrew.Visibility do
  @moduledoc """
  Who can see a homebrew project and its cards.

  - `:private` — the creator only.
  - `:unlisted` — anyone with the share link (`/custom/@username/slug`), but
    absent from every listing and from card-level search. Reachable only
    through the dedicated `HomebrewSet :by_creator_slug` and
    `Card :for_shared_set` reads; the default read filters never admit it.
  - `:published` — everyone, everywhere.
  """

  use Ash.Type.Enum, values: [:private, :unlisted, :published]
end
