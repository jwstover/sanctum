defmodule Sanctum.Search.ScenarioFields do
  @moduledoc """
  Search-field registry for scenarios (queries run against
  `Sanctum.Games.Scenario`). Minimal on purpose — scenarios only surface in
  the global search bar.
  """

  use Sanctum.Search.NameRegistry, example: "name:rhino", hint: "scenario name"

  defp name_expr(pattern), do: expr(ilike(name, ^pattern))
end
