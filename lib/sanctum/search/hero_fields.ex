defmodule Sanctum.Search.HeroFields do
  @moduledoc """
  Search-field registry for heroes (queries run against `Sanctum.Heroes.Hero`).
  Minimal on purpose — heroes only surface in the global search bar.
  """

  @behaviour Sanctum.Search.Registry

  import Ash.Expr

  alias Sanctum.Search.{Builders, Field}

  @impl true
  def bare_word(value) do
    name_expr(Builders.pattern(value))
  end

  @impl true
  def fields do
    [
      %Field{
        name: "name",
        aliases: ["n"],
        kind: :text,
        example: "name:spider-man",
        hint: "hero or alter-ego name",
        values_fun: &Sanctum.Search.Values.heroes/0,
        build: Builders.text_build(&name_expr/1)
      }
    ]
  end

  # display_name always contains hero_name, so it subsumes a hero_name match
  # while also matching the disambiguated "Black Panther (T'Challa)" form.
  defp name_expr(pattern) do
    expr(ilike(display_name, ^pattern) or ilike(alter_ego_name, ^pattern))
  end
end
