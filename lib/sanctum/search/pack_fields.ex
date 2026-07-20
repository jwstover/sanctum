defmodule Sanctum.Search.PackFields do
  @moduledoc """
  Search-field registry for packs (queries run against `Sanctum.Catalog.Pack`).
  Minimal on purpose — packs only surface in the global search bar.
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
        example: ~s(name:"sinister motives"),
        hint: "pack name",
        build: Builders.text_build(fn pattern -> expr(ilike(name, ^pattern)) end)
      }
    ]
  end
end
