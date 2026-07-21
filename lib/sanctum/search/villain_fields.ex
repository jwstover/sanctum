defmodule Sanctum.Search.VillainFields do
  @moduledoc """
  Search-field registry for villains (queries run against
  `Sanctum.Villains.Villain`). Minimal on purpose — villains only surface in
  the global search bar.
  """

  use Sanctum.Search.NameRegistry, example: "name:klaw", hint: "villain name"

  defp name_expr(pattern), do: expr(ilike(villain_name, ^pattern))
end
