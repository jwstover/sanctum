defmodule Sanctum.Search.Compiler do
  @moduledoc """
  Compiles a `Sanctum.Search.Parser` AST into an Ash filter expression using a
  field registry.

  Compilation is diagnostic-collecting, not failing: an unknown field drops
  its clause with a warning (the rest of the query still filters); a known
  field with an invalid value compiles to `false` (matches nothing) plus a
  did-you-mean diagnostic — `aspect = agression` should return zero rows *and*
  tell you why, not silently show everything.
  """

  import Ash.Expr

  alias Sanctum.Search.{Diagnostic, Field, Registry, Token}

  @doc "Compile an AST (or nil) into `{ash_expr | nil, diagnostics}`."
  @spec compile(term(), module()) :: {term() | nil, [Diagnostic.t()]}
  def compile(nil, _registry), do: {nil, []}
  def compile(ast, registry), do: node_expr(ast, registry)

  defp node_expr({:and, children}, registry), do: combine(children, registry, :and)
  defp node_expr({:or, children}, registry), do: combine(children, registry, :or)

  defp node_expr({:not, child}, registry) do
    case node_expr(child, registry) do
      {nil, diags} -> {nil, diags}
      {e, diags} -> {expr(not (^e)), diags}
    end
  end

  defp node_expr({:word, %Token{value: ""}}, _registry), do: {nil, []}

  defp node_expr({:word, %Token{value: value}}, registry),
    do: {registry.bare_word(value), []}

  defp node_expr({:clause, clause}, registry), do: clause_expr(clause, registry)

  defp combine(children, registry, kind) do
    {exprs, diags} =
      Enum.reduce(children, {[], []}, fn child, {exprs, diags} ->
        {e, d} = node_expr(child, registry)
        {if(is_nil(e), do: exprs, else: [e | exprs]), diags ++ d}
      end)

    {exprs |> Enum.reverse() |> join(kind), diags}
  end

  defp join([], _kind), do: nil
  defp join([one], _kind), do: one
  defp join([head | tail], :and), do: Enum.reduce(tail, head, &expr(^&2 and ^&1))
  defp join([head | tail], :or), do: Enum.reduce(tail, head, &expr(^&2 or ^&1))

  defp clause_expr(%{field: field_tok, op: op, op_token: op_tok, values: values}, registry) do
    case Registry.lookup(registry, field_tok.value) do
      nil ->
        {nil, [unknown_field(field_tok, registry)]}

      %Field{} = field ->
        if op in field.ops do
          values_expr(field, op, values)
        else
          message =
            ~s(the "#{field.name}" field doesn't support "#{op_tok.value}")

          {nil,
           [
             Diagnostic.new(:warning, :unsupported_operator, message, op_tok.start, op_tok.length)
           ]}
        end
    end
  end

  # Each `|`-separated value builds its own expression. Alternatives combine
  # with OR for positive matches and AND for `!=` ("neither x nor y").
  defp values_expr(field, op, value_tokens) do
    {exprs, diags} =
      Enum.reduce(value_tokens, {[], []}, fn %Token{} = tok, {exprs, diags} ->
        case field.build.(op, tok.value) do
          {:ok, e} ->
            {[e | exprs], diags}

          {:error, message} ->
            diag =
              Diagnostic.new(:warning, :invalid_value, message, tok.start, tok.length)

            {exprs, diags ++ [diag]}
        end
      end)

    case {exprs, diags} do
      # Every value was invalid on a known field: match nothing (and say why).
      {[], [_ | _]} ->
        {expr(false), diags}

      {exprs, diags} ->
        {exprs |> Enum.reverse() |> join(if op == :neq, do: :and, else: :or), diags}
    end
  end

  defp unknown_field(%Token{} = tok, registry) do
    suggestion =
      case Registry.suggest(registry, tok.value) do
        nil -> ""
        name -> ~s( — did you mean "#{name}"?)
      end

    Diagnostic.new(
      :warning,
      :unknown_field,
      ~s(unknown field "#{tok.value}"#{suggestion}),
      tok.start,
      tok.length
    )
  end
end
