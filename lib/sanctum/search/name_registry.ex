defmodule Sanctum.Search.NameRegistry do
  @moduledoc """
  Shared implementation for the minimal single-field registries the global
  search fans out to (packs, heroes, villains, scenarios, card sets): one
  `name` text field plus the bare-word fallback, both matching through the
  same `pattern -> Ash expression` function.

  Ash expression macros bind resource attributes at compile time, so each
  registry defines only that expression:

      use Sanctum.Search.NameRegistry, example: "name:klaw", hint: "villain name"

      defp name_expr(pattern), do: expr(ilike(villain_name, ^pattern))

  `fields/0` is overridable for registries with extra fields (card sets'
  `set_type`) — append to `super()`.
  """

  alias Sanctum.Search.{Builders, Field}

  defmacro __using__(opts) do
    quote do
      @behaviour Sanctum.Search.Registry

      import Ash.Expr

      alias Sanctum.Search.NameRegistry

      @impl true
      def bare_word(value), do: NameRegistry.bare_word(&name_expr/1, value)

      @impl true
      def fields do
        [NameRegistry.name_field(&name_expr/1, unquote(opts))]
      end

      defoverridable fields: 0
    end
  end

  @doc "The bare-word fallback: the registry's name expression, pattern-escaped."
  def bare_word(to_expr, value), do: to_expr.(Builders.pattern(value))

  @doc """
  The `name` text field built on `to_expr`. Options: `:example` and `:hint`
  (required), `:values_fun` (optional autocomplete source).
  """
  def name_field(to_expr, opts) do
    %Field{
      name: "name",
      aliases: ["n"],
      kind: :text,
      example: Keyword.fetch!(opts, :example),
      hint: Keyword.fetch!(opts, :hint),
      values_fun: opts[:values_fun],
      build: Builders.text_build(to_expr)
    }
  end
end
