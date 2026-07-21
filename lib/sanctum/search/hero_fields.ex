defmodule Sanctum.Search.HeroFields do
  @moduledoc """
  Search-field registry for heroes (queries run against `Sanctum.Heroes.Hero`).
  Minimal on purpose — heroes only surface in the global search bar.
  """

  use Sanctum.Search.NameRegistry,
    example: "name:spider-man",
    hint: "hero or alter-ego name",
    values_fun: &Sanctum.Search.Values.heroes/0

  # display_name always contains hero_name, so it subsumes a hero_name match
  # while also matching the disambiguated "Black Panther (T'Challa)" form.
  defp name_expr(pattern) do
    expr(ilike(display_name, ^pattern) or ilike(alter_ego_name, ^pattern))
  end
end
