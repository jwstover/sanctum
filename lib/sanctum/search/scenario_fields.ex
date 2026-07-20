defmodule Sanctum.Search.ScenarioFields do
  @moduledoc """
  Search-field registry for scenarios (queries run against
  `Sanctum.Games.Scenario`). Minimal on purpose — scenarios only surface in
  the global search bar.
  """

  @behaviour Sanctum.Search.Registry

  import Ash.Expr

  alias Sanctum.Search.{Builders, Field}

  @impl true
  def bare_word(value) do
    expr(ilike(name, ^Builders.pattern(value)))
  end

  @impl true
  def fields do
    [
      %Field{
        name: "name",
        aliases: ["n"],
        kind: :text,
        example: "name:rhino",
        hint: "scenario name",
        build: Builders.text_build(fn pattern -> expr(ilike(name, ^pattern)) end)
      }
    ]
  end
end
