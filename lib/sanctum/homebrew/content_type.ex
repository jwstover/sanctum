defmodule Sanctum.Homebrew.ContentType do
  @moduledoc """
  What kinds of content a homebrew project contains. Type is chosen per-upload
  (the project page's Upload chooser), not declared at project creation — this
  is intended to be *derived* from what a project actually holds. A project can
  span several kinds, so it's an array on the project, not a single tag. Stored
  as `{:array, :text}`, so adding a value here needs no migration.
  """

  use Ash.Type.Enum,
    values: [
      :alt_art,
      :hero,
      :player_cards,
      :villain_scenario,
      :modular_set,
      :campaign,
      :aspect,
      :other
    ]
end
