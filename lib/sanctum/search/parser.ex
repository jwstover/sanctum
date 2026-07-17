defmodule Sanctum.Search.Parser do
  @moduledoc """
  Error-tolerant recursive-descent parser over `Sanctum.Search.Lexer` tokens.

  Produces an AST of:

    * `{:and, [node]}` / `{:or, [node]}` — boolean combinations (space between
      terms is an implicit AND, Scryfall-style)
    * `{:not, node}` — negation (`-term` or `NOT term`)
    * `{:clause, %{field:, op:, values:}}` — a `field op value` term; `values`
      holds one token per `|`-separated alternative (`aspect:justice|leadership`)
    * `{:word, token}` — a bare word or quoted phrase (full-text fallback)

  The parser never fails. Malformed input — a trailing `cost <`, a stray `)`,
  an operator with no field — is dropped with a `Diagnostic` while the valid
  remainder still parses, so results stay live while the user types.
  """

  alias Sanctum.Search.{Diagnostic, Lexer, Token}

  @type ast ::
          {:and, [ast]}
          | {:or, [ast]}
          | {:not, ast}
          | {:clause, %{field: Token.t(), op: atom(), op_token: Token.t(), values: [Token.t()]}}
          | {:word, Token.t()}

  @op_map %{
    ":" => :eq,
    "=" => :eq,
    "!=" => :neq,
    "!" => :neq,
    "<" => :lt,
    ">" => :gt,
    "<=" => :lte,
    ">=" => :gte
  }

  @doc "Parse `input` into `{ast | nil, diagnostics}`. Never raises."
  @spec parse(String.t()) :: {ast() | nil, [Diagnostic.t()]}
  def parse(input) when is_binary(input) do
    tokens = Lexer.tokenize(input)
    {node, rest, diags} = parse_or(tokens, 0)

    # Defensive: at depth 0 the grammar consumes all input, but if anything
    # ever remains, drop it rather than loop or crash.
    extra_diags =
      case rest do
        [] -> []
        [%Token{} = t | _] -> [stray(t)]
      end

    {node, diags ++ extra_diags}
  end

  # -- or-level ---------------------------------------------------------------

  defp parse_or(tokens, depth) do
    {left, rest, diags} = parse_and(tokens, depth)
    parse_or_tail(left, rest, depth, diags)
  end

  defp parse_or_tail(left, [%Token{kind: :word, value: v} | rest] = tokens, depth, diags) do
    if String.downcase(v) == "or" do
      {right, rest2, d2} = parse_and(rest, depth)
      parse_or_tail(merge(:or, left, right), rest2, depth, diags ++ d2)
    else
      {left, tokens, diags}
    end
  end

  defp parse_or_tail(left, tokens, _depth, diags), do: {left, tokens, diags}

  # -- and-level (implicit between adjacent terms) ----------------------------

  defp parse_and(tokens, depth) do
    {term, rest, diags} = parse_term(tokens, depth)
    parse_and_tail(add_term([], term), rest, depth, diags)
  end

  defp parse_and_tail(terms, [] = rest, _depth, diags), do: {and_node(terms), rest, diags}

  defp parse_and_tail(terms, [%Token{kind: :rparen} | _] = rest, depth, diags) when depth > 0 do
    {and_node(terms), rest, diags}
  end

  defp parse_and_tail(terms, [%Token{kind: :rparen} = t | rest], depth, diags) when depth == 0 do
    parse_and_tail(terms, rest, depth, diags ++ [stray(t)])
  end

  defp parse_and_tail(terms, [%Token{kind: k} = t | rest], depth, diags) when k in [:op, :pipe] do
    parse_and_tail(terms, rest, depth, diags ++ [stray(t)])
  end

  defp parse_and_tail(terms, [%Token{kind: :word, value: v} | rest] = tokens, depth, diags) do
    case String.downcase(v) do
      "or" ->
        {and_node(terms), tokens, diags}

      "and" ->
        {term, rest2, d} = parse_term(rest, depth)
        parse_and_tail(add_term(terms, term), rest2, depth, diags ++ d)

      _ ->
        {term, rest2, d} = parse_term(tokens, depth)
        parse_and_tail(add_term(terms, term), rest2, depth, diags ++ d)
    end
  end

  defp parse_and_tail(terms, tokens, depth, diags) do
    {term, rest, d} = parse_term(tokens, depth)
    parse_and_tail(add_term(terms, term), rest, depth, diags ++ d)
  end

  # -- terms -------------------------------------------------------------------

  defp parse_term([], _depth), do: {nil, [], []}

  defp parse_term([%Token{kind: :rparen} | _] = tokens, depth) when depth > 0,
    do: {nil, tokens, []}

  defp parse_term([%Token{kind: :neg} | rest], depth) do
    {node, rest2, diags} = parse_term(rest, depth)
    {negate(node), rest2, diags}
  end

  defp parse_term([%Token{kind: :lparen} = lp | rest], depth) do
    {node, rest2, diags} = parse_or(rest, depth + 1)

    case rest2 do
      [%Token{kind: :rparen} | rest3] ->
        {node, rest3, diags}

      _ ->
        diag =
          Diagnostic.new(:warning, :unclosed_paren, "unclosed parenthesis", lp.start, lp.length)

        {node, rest2, diags ++ [diag]}
    end
  end

  defp parse_term([%Token{kind: :string} = t | rest], _depth), do: {{:word, t}, rest, []}

  defp parse_term([%Token{kind: :word} = t, %Token{kind: :op} = op | rest], _depth) do
    parse_clause(t, op, rest)
  end

  defp parse_term([%Token{kind: :word, value: v} = t | rest], depth) do
    if String.downcase(v) == "not" and starts_term?(rest) do
      {node, rest2, diags} = parse_term(rest, depth)
      {negate(node), rest2, diags}
    else
      {{:word, t}, rest, []}
    end
  end

  # Stray operator/pipe at term position: skip it.
  defp parse_term([%Token{} = t | rest], _depth), do: {nil, rest, [stray(t)]}

  defp parse_clause(field_tok, op_tok, rest) do
    case take_values(rest, []) do
      {[], rest2} ->
        span_end = op_tok.start + op_tok.length

        diag =
          Diagnostic.new(
            :warning,
            :incomplete_clause,
            ~s(incomplete "#{field_tok.value}" filter — expected a value after "#{op_tok.value}"),
            field_tok.start,
            span_end - field_tok.start
          )

        {nil, rest2, [diag]}

      {values, rest2} ->
        node =
          {:clause,
           %{
             field: field_tok,
             op: Map.fetch!(@op_map, op_tok.value),
             op_token: op_tok,
             values: values
           }}

        {node, rest2, []}
    end
  end

  defp take_values([%Token{kind: k} = v | rest], []) when k in [:word, :string],
    do: take_values(rest, [v])

  defp take_values([%Token{kind: :pipe}, %Token{kind: k} = v | rest], acc)
       when acc != [] and k in [:word, :string],
       do: take_values(rest, [v | acc])

  # Trailing pipe with no value: stop; the pipe token is left for the
  # and-level to report as stray.
  defp take_values(rest, acc), do: {Enum.reverse(acc), rest}

  defp starts_term?([%Token{kind: k} | _]) when k in [:word, :string, :lparen, :neg], do: true
  defp starts_term?(_), do: false

  # -- node assembly -----------------------------------------------------------

  defp add_term(terms, nil), do: terms
  defp add_term(terms, term), do: terms ++ [term]

  defp and_node([]), do: nil
  defp and_node([one]), do: one
  defp and_node(terms), do: {:and, terms}

  defp merge(_kind, left, nil), do: left
  defp merge(_kind, nil, right), do: right
  defp merge(kind, {kind, items}, right), do: {kind, items ++ [right]}
  defp merge(kind, left, right), do: {kind, [left, right]}

  defp negate(nil), do: nil
  defp negate(node), do: {:not, node}

  defp stray(%Token{} = t) do
    Diagnostic.new(:warning, :stray_token, ~s(unexpected "#{t.value}"), t.start, t.length)
  end
end
