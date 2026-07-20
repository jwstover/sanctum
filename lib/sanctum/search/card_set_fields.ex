defmodule Sanctum.Search.CardSetFields do
  @moduledoc """
  Search-field registry for card sets (queries run against
  `Sanctum.Catalog.CardSet`). Minimal on purpose — card sets only surface in
  the global search bar.
  """

  @behaviour Sanctum.Search.Registry

  import Ash.Expr

  alias Sanctum.Catalog.SetType
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
        example: ~s(name:"weapon x"),
        hint: "card set name",
        build: Builders.text_build(fn pattern -> expr(ilike(name, ^pattern)) end)
      },
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
end
