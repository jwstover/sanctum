defmodule SanctumWeb.CardFilters do
  @moduledoc """
  Shared filter-pill option lists for the browse pages (card pool, deck
  browser, deckbuilder): `{key, label}` card types and `{key, label, css}`
  aspects. Keys travel through URL params, so they're strings.
  """

  @aspects [
    {"all", "All", nil},
    {"hero", "Hero", "bg-aspect-hero"},
    {"aggression", "Aggression", "bg-aspect-aggression"},
    {"justice", "Justice", "bg-aspect-justice"},
    {"leadership", "Leadership", "bg-aspect-leadership"},
    {"protection", "Protection", "bg-aspect-protection"},
    {"pool", "Pool", "bg-aspect-pool"},
    {"basic", "Basic", "bg-aspect-basic"}
  ]

  @types [
    {"all", "All"},
    {"ally", "Ally"},
    {"event", "Event"},
    {"support", "Support"},
    {"upgrade", "Upgrade"},
    {"resource", "Resource"},
    {"player_side_scheme", "Side Scheme"}
  ]

  @doc "Every aspect option, including the hero pseudo-aspect (card pool)."
  def aspect_options, do: @aspects

  @doc "Aspect options for deck surfaces, where hero isn't a choice."
  def deck_aspect_options, do: Enum.reject(@aspects, fn {key, _, _} -> key == "hero" end)

  @doc "Player card type options."
  def type_options, do: @types
end
