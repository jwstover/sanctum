defmodule Sanctum.Homebrew.ContentType do
  @moduledoc """
  What kinds of content a homebrew project contains — a project can span
  several (e.g. a campaign that ships a hero and modular sets).
  """

  use Ash.Type.Enum,
    values: [:hero, :villain_scenario, :modular_set, :campaign, :aspect, :other]
end
