defmodule Sanctum.Search.CardSetFields do
  @moduledoc """
  Search-field registry for card sets (queries run against
  `Sanctum.Catalog.CardSet`). Minimal on purpose — card sets only surface in
  the global search bar.
  """

  use Sanctum.Search.NameRegistry,
    example: ~s(name:"weapon x"),
    hint: "card set name"

  alias Sanctum.Catalog.SetType
  alias Sanctum.Search.{Builders, Field}

  @impl true
  def fields do
    super() ++
      [
        %Field{
          name: "set_type",
          aliases: ["settype"],
          kind: :enum,
          values: Enum.map(SetType.values(), &to_string/1),
          example: "set_type:modular",
          hint: "role of the set (modular, nemesis, …)",
          build: fn op, value ->
            with {:ok, atom} <- Builders.coerce_enum(value, SetType.values()) do
              {:ok, Builders.cmp(expr(set_type), op, atom)}
            end
          end
        }
      ]
  end

  defp name_expr(pattern), do: expr(ilike(name, ^pattern))
end
