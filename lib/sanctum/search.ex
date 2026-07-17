defmodule Sanctum.Search do
  @moduledoc """
  The advanced search query language for cards and decks.

  Users type Scryfall-style queries — `aspect = aggression AND cost <= 2 AND
  type = ally`, or the terse MarvelCDB-flavored `a:aggression c<=2 t:ally` —
  and this module turns them into Ash filter expressions.

  Language summary:

    * `field op value` terms; `:` and `=` both mean equals; `!=` `<` `>` `<=`
      `>=` where the field supports them
    * space between terms is an implicit AND; `or` and parentheses group
    * `-term` or `not term` negates
    * `value|value` is a value-level OR (`aspect:justice|leadership`)
    * `"quoted strings"` for multi-word values
    * a bare word searches names (cards: name/subname; decks: title/hero)
    * everything is case-insensitive; malformed pieces degrade gracefully
      with diagnostics instead of failing the whole query

  Fields are defined per surface in `Sanctum.Search.CardFields` and
  `Sanctum.Search.DeckFields` — the registries are the allowlist of what a
  query can touch.
  """

  alias Sanctum.Search.{Compiler, Diagnostic, Parser}

  @type result :: %{
          ast: Parser.ast() | nil,
          expr: term() | nil,
          diagnostics: [Diagnostic.t()]
        }

  @doc """
  Parse and compile `input` against a field registry.

  Returns `%{ast:, expr:, diagnostics:}`. `expr` is an Ash expression ready
  for `Ash.Query.filter(query, ^expr)`, or nil when the input contains no
  usable terms (empty/whitespace/only malformed pieces — callers should apply
  no filter in that case).
  """
  @spec compile(String.t(), module()) :: result()
  def compile(input, registry) when is_binary(input) do
    {ast, parse_diags} = Parser.parse(input)
    {expr, compile_diags} = Compiler.compile(ast, registry)
    %{ast: ast, expr: expr, diagnostics: parse_diags ++ compile_diags}
  end

  @doc "Parse `input` into `{ast | nil, diagnostics}` without compiling."
  defdelegate parse(input), to: Parser
end
