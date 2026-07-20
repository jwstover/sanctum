defmodule Sanctum.Search.VillainFields do
  @moduledoc """
  Search-field registry for villains (queries run against
  `Sanctum.Villains.Villain`). Minimal on purpose — villains only surface in
  the global search bar.
  """

  @behaviour Sanctum.Search.Registry

  import Ash.Expr

  alias Sanctum.Search.{Builders, Field}

  @impl true
  def bare_word(value) do
    expr(ilike(villain_name, ^Builders.pattern(value)))
  end

  @impl true
  def fields do
    [
      %Field{
        name: "name",
        aliases: ["n"],
        kind: :text,
        example: "name:klaw",
        hint: "villain name",
        build: Builders.text_build(fn pattern -> expr(ilike(villain_name, ^pattern)) end)
      }
    ]
  end
end
