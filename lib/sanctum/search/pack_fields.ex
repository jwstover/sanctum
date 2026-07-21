defmodule Sanctum.Search.PackFields do
  @moduledoc """
  Search-field registry for packs (queries run against `Sanctum.Catalog.Pack`).
  Minimal on purpose — packs only surface in the global search bar.
  """

  use Sanctum.Search.NameRegistry,
    example: ~s(name:"sinister motives"),
    hint: "pack name"

  defp name_expr(pattern), do: expr(ilike(name, ^pattern))
end
