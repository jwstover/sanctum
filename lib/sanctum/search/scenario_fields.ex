defmodule Sanctum.Search.ScenarioFields do
  @moduledoc """
  Search-field registry for scenarios (queries run against
  `Sanctum.Games.Scenario`): the scenario browser's `:browse` action and the
  global search bar's Scenarios group.
  """

  @behaviour Sanctum.Search.Registry

  import Ash.Expr

  alias Sanctum.Search.{Builders, Field}

  @flags ["mine", "official"]

  @impl true
  def bare_word(value) do
    pattern = Builders.pattern(value)
    expr(ilike(name, ^pattern) or ^villain_set_expr(pattern) or ^modular_expr(pattern))
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
        build: Builders.text_build(&name_expr/1)
      },
      %Field{
        name: "villain",
        aliases: ["v"],
        kind: :text,
        example: "villain:rhino",
        hint: "villain set name or code",
        build: Builders.text_build(&villain_set_expr/1)
      },
      %Field{
        name: "set",
        aliases: ["modular"],
        kind: :text,
        example: ~s(set:"bomb scare"),
        hint: "modular encounter set name or code",
        build: Builders.text_build(&modular_expr/1)
      },
      %Field{
        name: "is",
        aliases: [],
        kind: :flag,
        values: @flags,
        example: "is:mine",
        hint: "mine (needs sign-in) or official",
        ops: [:eq],
        form: %{group: "Scenario", order: 10, label: "Scenario is…"},
        build: &flag_build/2
      }
    ]
  end

  defp name_expr(pattern), do: expr(ilike(name, ^pattern))

  defp villain_set_expr(pattern),
    do: expr(ilike(villain_set.name, ^pattern) or ilike(villain_set.code, ^pattern))

  defp modular_expr(pattern),
    do: expr(exists(modular_sets, ilike(name, ^pattern) or ilike(code, ^pattern)))

  defp flag_build(:eq, value) do
    with {:ok, flag} <- Builders.coerce_enum(value, @flags), do: {:ok, flag_expr(flag)}
  end

  # `mine` compares owner_id to the actor's id, so it matches nothing signed out.
  defp flag_expr("mine"), do: expr(mine == true)
  defp flag_expr("official"), do: expr(official == true)
end
