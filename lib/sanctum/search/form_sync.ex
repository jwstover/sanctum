defmodule Sanctum.Search.FormSync do
  @moduledoc """
  Two-way sync between a search query string and the structured filter form
  described by `Sanctum.Search.FormSchema`.

  `read/2` extracts the form-representable clauses out of a query string;
  `update/3` splices form changes back into it. The contract: everything the
  form does not manage — OR groups, negations, bare words, invalid values,
  duplicate clauses, fields without a sheet control — is *residual*, and its
  bytes are never touched. Edits splice byte ranges (tokens carry source
  spans), so an in-place change reuses the user's original field alias and
  operator spelling (`a=justice` stays `a=…`), and an untouched form submit
  returns the input verbatim, whitespace included.

  A clause is managed iff all of:

    * it is a top-level AND conjunct at paren depth 0 (the parser flattens
      `(t:ally)`, so depth is re-checked against the token stream)
    * it uses a positive `:eq` operator — except `:number` controls, which
      accept any operator the field supports
    * its field has a sheet control (`FormSchema.control_for/1`)
    * every value validates for that control (enum membership, vocabulary
      match, boolean literal, or the field's own `build` for numbers)

  Only the first clause per field is managed (`t:ally t:event` keeps its
  match-nothing AND semantics: the second stays residual). `:checks` flags
  are the exception — each single-value `is:x` clause is managed on its own,
  since checkbox-group AND matches query AND.
  """

  alias Sanctum.Search.{Field, FormSchema, Lexer, Parser, Registry, Token}

  @typedoc """
  Form value shapes by control: lists for `:chips`/`:checks`, a bare string
  for `:tristate`/`:toggle`/`:select` (`""` = unset), `%{op, value}` for
  `:number` (blank value = unset).
  """
  @type form_value :: [String.t()] | String.t() | %{op: Field.op(), value: String.t()}

  @op_strings %{eq: ":", neq: "!=", lt: "<", gt: ">", lte: "<=", gte: ">="}

  # Characters that force a rendered value into quotes — the lexer's word
  # stops, plus a leading "-" (which would lex as negation).
  @quote_triggers [" ", "\t", "\n", "\r", "\"", "(", ")", "|", ":", "<", ">", "=", "!"]

  @doc """
  Read the form state out of `input`: `fields` maps managed field names to
  their `t:form_value/0`; `residual` is the rest of the query (display only —
  `update/3` preserves residual bytes from `input` itself).
  """
  @spec read(String.t(), module()) :: %{
          fields: %{String.t() => form_value()},
          residual: String.t()
        }
  def read(input, registry) do
    analysis = analyze(input, registry)
    %{fields: adopted_fields(analysis), residual: residual(analysis)}
  end

  @doc """
  Splice form changes into `input`. Only fields present in `new_fields` are
  touched (an absent key leaves that field's clause alone); an empty value
  (`[]`, `""`, blank number) removes the field's clause. Unchanged values
  produce zero edits. New clauses append in registry order, canonical form.
  """
  @spec update(String.t(), module(), %{String.t() => form_value()}) :: String.t()
  def update(input, registry, new_fields) do
    analysis = analyze(input, registry)

    {edits, appends} =
      new_fields
      |> changes(registry)
      |> Enum.reduce({[], []}, fn {field, control, new_value}, {edits, appends} ->
        entries = Map.get(analysis.adopted, field.name, [])
        diff(control, field, entries, new_value, edits, appends)
      end)

    apply_edits(input, edits, appends)
  end

  @doc """
  How many filters the query expresses: every selected value across managed
  fields, plus one per residual conjunct that is not a bare word (bare words
  are name search, not a filter).
  """
  @spec active_count(String.t(), module()) :: non_neg_integer()
  def active_count(input, registry) do
    analysis = analyze(input, registry)

    managed =
      analysis.adopted
      |> Map.values()
      |> List.flatten()
      |> Enum.map(fn
        %{value: values} when is_list(values) -> length(values)
        _entry -> 1
      end)
      |> Enum.sum()

    residual =
      Enum.count(analysis.residual_nodes, fn
        {:word, _token} -> false
        _node -> true
      end)

    managed + residual
  end

  @doc """
  Build an `update/3` fields map out of a filter-sheet `phx-change` payload.
  Only params named after managed fields are picked up; `:number` fields read
  `"<name>"` and `"<name>_op"`. Keys absent from `params` stay absent (their
  clauses untouched); the sheet form submits every control, so a full submit
  is a full sync.
  """
  @spec fields_from_params(map(), module()) :: %{String.t() => form_value()}
  def fields_from_params(params, registry) do
    registry.fields()
    |> Enum.reduce(%{}, fn field, acc ->
      case {FormSchema.control_for(field), Map.fetch(params, field.name)} do
        {nil, _} ->
          acc

        {_control, :error} ->
          acc

        {control, {:ok, raw}} ->
          Map.put(acc, field.name, param_value(control, field, raw, params))
      end
    end)
  end

  defp param_value(control, _field, raw, _params) when control in [:chips, :checks],
    do: raw |> List.wrap() |> Enum.reject(&(&1 in [nil, ""]))

  defp param_value(:number, field, raw, params),
    do: %{op: params["#{field.name}_op"] || :eq, value: to_string(raw)}

  defp param_value(_control, _field, raw, _params), do: to_string(raw)

  # -- analysis ---------------------------------------------------------------

  defp analyze(input, registry) do
    tokens = Lexer.tokenize(input)
    depths = depth_map(tokens)
    {ast, _diags} = Parser.parse(input)

    {adopted, residual_nodes} =
      ast
      |> conjuncts()
      |> Enum.reduce({%{}, []}, fn node, {adopted, residual} ->
        case adopt(node, registry, input, tokens, depths, adopted) do
          {:ok, name, entry} -> {Map.update(adopted, name, [entry], &(&1 ++ [entry])), residual}
          :residual -> {adopted, residual ++ [node]}
        end
      end)

    %{input: input, adopted: adopted, residual_nodes: residual_nodes}
  end

  defp conjuncts(nil), do: []
  defp conjuncts({:and, children}), do: children
  defp conjuncts(node), do: [node]

  # Paren depth per token start offset. The parser flattens grouped clauses
  # into the AST, so depth must come from the raw token stream.
  defp depth_map(tokens) do
    tokens
    |> Enum.reduce({%{}, 0}, fn token, {map, depth} ->
      case token.kind do
        :lparen -> {Map.put(map, token.start, depth), depth + 1}
        :rparen -> {Map.put(map, token.start, max(depth - 1, 0)), max(depth - 1, 0)}
        _ -> {Map.put(map, token.start, depth), depth}
      end
    end)
    |> elem(0)
  end

  defp adopt(
         {:clause, %{field: field_tok, op: op, op_token: op_tok, values: value_toks}},
         registry,
         input,
         tokens,
         depths,
         adopted
       ) do
    with 0 <- Map.get(depths, field_tok.start, 0),
         %Field{} = field <- Registry.lookup(registry, field_tok.value),
         control when not is_nil(control) <- FormSchema.control_for(field),
         {:ok, value} <- adopt_value(control, field, op, value_toks),
         :ok <- dedup(adopted, field.name, control, value) do
      last = List.last(value_toks)
      span = {field_tok.start, last.start + last.length}

      entry = %{
        control: control,
        op: op,
        value: value,
        span: span,
        del_span: extend_over_and(span, tokens, depths),
        field_src: slice(input, field_tok),
        op_src: slice(input, op_tok)
      }

      {:ok, field.name, entry}
    else
      _ -> :residual
    end
  end

  defp adopt(_node, _registry, _input, _tokens, _depths, _adopted), do: :residual

  defp slice(input, %Token{start: start, length: length}),
    do: binary_part(input, start, length)

  defp adopt_value(:chips, field, :eq, value_toks) do
    values = Enum.map(value_toks, &Registry.normalize(&1.value))
    if Enum.all?(values, &(&1 in field.values)), do: {:ok, Enum.uniq(values)}, else: :error
  end

  defp adopt_value(:checks, field, :eq, [value_tok]) do
    value = Registry.normalize(value_tok.value)
    if value in field.values, do: {:ok, [value]}, else: :error
  end

  defp adopt_value(control, _field, :eq, [value_tok]) when control in [:tristate, :toggle] do
    value = Registry.normalize(value_tok.value)
    if value in ["true", "false"], do: {:ok, value}, else: :error
  end

  # Adopt the vocabulary's own spelling so the <select> option matches.
  defp adopt_value(:select, field, :eq, [value_tok]) do
    normalized = Registry.normalize(value_tok.value)

    (field.values ++ dynamic_values(field))
    |> Enum.find(&(Registry.normalize(&1) == normalized))
    |> case do
      nil -> :error
      match -> {:ok, match}
    end
  end

  # The field's own build is the authoritative validator — it knows which
  # ops each field takes and whether "x" is a legal value.
  defp adopt_value(:number, field, op, [value_tok]) do
    value = String.trim(value_tok.value)

    with true <- op in field.ops,
         {:ok, _expr} <- field.build.(op, value) do
      {:ok, %{op: op, value: value}}
    else
      _ -> :error
    end
  end

  defp adopt_value(_control, _field, _op, _value_toks), do: :error

  defp dynamic_values(%Field{values_fun: fun}) when is_function(fun, 0), do: fun.()
  defp dynamic_values(_field), do: []

  defp dedup(adopted, name, :checks, [value]) do
    already = adopted |> Map.get(name, []) |> Enum.flat_map(& &1.value)
    if value in already, do: :residual, else: :ok
  end

  defp dedup(adopted, name, _control, _value),
    do: if(Map.has_key?(adopted, name), do: :residual, else: :ok)

  # Deleting a clause also swallows one adjacent standalone depth-0 "and",
  # so `t:ally and cost:2` minus the type clause leaves `cost:2`, not a bare
  # "and" that would parse as a name search.
  defp extend_over_and({start, stop} = span, tokens, depths) do
    following = Enum.find(tokens, &(&1.start >= stop))
    preceding = tokens |> Enum.take_while(&(&1.start < start)) |> List.last()

    cond do
      and_word?(following, depths) -> {start, following.start + following.length}
      and_word?(preceding, depths) -> {preceding.start, stop}
      true -> span
    end
  end

  defp and_word?(%Token{kind: :word, value: value, start: start}, depths),
    do: String.downcase(value) == "and" and Map.get(depths, start, 0) == 0

  defp and_word?(_token, _depths), do: false

  defp adopted_fields(%{adopted: adopted}) do
    Map.new(adopted, fn {name, entries} ->
      case entries do
        [%{control: :checks} | _] -> {name, Enum.flat_map(entries, & &1.value)}
        [entry] -> {name, entry.value}
      end
    end)
  end

  defp residual(%{input: input, adopted: adopted}) do
    spans = adopted |> Map.values() |> List.flatten() |> Enum.map(& &1.del_span)

    input
    |> delete_ranges(spans)
    |> String.trim()
  end

  # -- diffing -----------------------------------------------------------------

  # Normalize the caller's fields map into `{field, control, clean_value}`
  # in registry order (so appended clauses come out deterministic).
  defp changes(new_fields, registry) do
    registry.fields()
    |> Enum.flat_map(fn field ->
      with control when not is_nil(control) <- FormSchema.control_for(field),
           {:ok, raw} <- Map.fetch(new_fields, field.name) do
        [{field, control, clean_value(control, field, raw)}]
      else
        _ -> []
      end
    end)
  end

  defp clean_value(control, _field, raw) when control in [:chips, :checks] do
    raw
    |> List.wrap()
    |> Enum.map(&Registry.normalize(to_string(&1)))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp clean_value(control, _field, raw) when control in [:tristate, :toggle],
    do: raw |> to_string() |> Registry.normalize()

  defp clean_value(:select, _field, raw), do: raw |> to_string() |> String.trim()

  defp clean_value(:number, field, %{} = raw) do
    value = (raw[:value] || raw["value"] || "") |> to_string() |> String.trim()
    %{op: clean_op(raw[:op] || raw["op"], field), value: value}
  end

  defp clean_value(:number, field, raw),
    do: %{op: default_op(field), value: raw |> to_string() |> String.trim()}

  defp clean_op(op, field) when is_atom(op) and not is_nil(op),
    do: if(op in field.ops, do: op, else: default_op(field))

  defp clean_op(op, field) when is_binary(op),
    do: Enum.find(field.ops, default_op(field), &(to_string(&1) == op))

  defp clean_op(_op, field), do: default_op(field)

  defp default_op(%Field{ops: ops}), do: if(:eq in ops, do: :eq, else: hd(ops))

  defp diff(:checks, field, entries, new_values, edits, appends) do
    old_values = Enum.flat_map(entries, & &1.value)

    deletes =
      entries
      |> Enum.reject(fn %{value: [value]} -> value in new_values end)
      |> Enum.map(&{:delete, &1.del_span})

    adds =
      new_values
      |> Enum.reject(&(&1 in old_values))
      |> Enum.map(&render_clause(field.name, :eq, [&1]))

    {edits ++ deletes, appends ++ adds}
  end

  defp diff(control, field, entries, new_value, edits, appends) do
    old_value =
      case entries do
        [entry] -> entry.value
        [] -> nil
      end

    cond do
      same_value?(control, old_value, new_value) ->
        {edits, appends}

      empty_value?(control, new_value) ->
        case entries do
          [entry] -> {edits ++ [{:delete, entry.del_span}], appends}
          [] -> {edits, appends}
        end

      entries == [] ->
        {edits, appends ++ [render_new(control, field, new_value)]}

      true ->
        [entry] = entries
        {edits ++ [{:replace, entry.span, render_edit(control, entry, new_value)}], appends}
    end
  end

  defp same_value?(:chips, old, new) when is_list(old) and is_list(new),
    do: MapSet.new(old) == MapSet.new(new)

  defp same_value?(:number, %{op: op, value: value}, %{op: op, value: value}), do: true
  defp same_value?(:number, _old, _new), do: false
  defp same_value?(_control, old, new), do: old == new

  defp empty_value?(:chips, new), do: new == []
  defp empty_value?(:number, %{value: value}), do: value == ""
  defp empty_value?(_control, new), do: new in [nil, ""]

  # In-place edits keep the user's field alias and operator spelling.
  defp render_edit(:chips, entry, new_values),
    do: entry.field_src <> entry.op_src <> render_values(new_values)

  defp render_edit(:number, entry, %{op: op, value: value}) do
    op_src = if op == entry.op, do: entry.op_src, else: Map.fetch!(@op_strings, op)
    entry.field_src <> op_src <> render_value(value)
  end

  defp render_edit(_control, entry, new_value),
    do: entry.field_src <> entry.op_src <> render_value(new_value)

  defp render_new(:number, field, %{op: op, value: value}),
    do: field.name <> Map.fetch!(@op_strings, op) <> render_value(value)

  defp render_new(:chips, field, new_values), do: render_clause(field.name, :eq, new_values)
  defp render_new(_control, field, new_value), do: render_clause(field.name, :eq, [new_value])

  defp render_clause(name, op, values),
    do: name <> Map.fetch!(@op_strings, op) <> render_values(values)

  defp render_values(values), do: Enum.map_join(values, "|", &render_value/1)

  # No escape syntax exists for quotes, so embedded quotes are stripped;
  # anything containing a word-stop (or a leading "-", which would lex as
  # negation) is quoted.
  defp render_value(value) do
    value = String.replace(value, "\"", "")

    if value == "" or String.starts_with?(value, "-") or String.contains?(value, @quote_triggers) do
      ~s(") <> value <> ~s(")
    else
      value
    end
  end

  # -- splicing ----------------------------------------------------------------

  defp apply_edits(input, [], []), do: input

  defp apply_edits(input, edits, appends) do
    deletes =
      for {:delete, range} <- edits do
        {extend_whitespace(range, input), ""}
      end
      |> merge_deletes()

    replaces = for {:replace, range, text} <- edits, do: {range, text}

    spliced =
      (deletes ++ replaces)
      |> Enum.sort_by(fn {{start, _stop}, _text} -> -start end)
      |> Enum.reduce(input, fn {{start, stop}, text}, acc ->
        binary_part(acc, 0, start) <> text <> binary_part(acc, stop, byte_size(acc) - stop)
      end)

    case appends do
      [] -> spliced
      _ -> Enum.join([String.trim(spliced) | appends] |> Enum.reject(&(&1 == "")), " ")
    end
  end

  defp delete_ranges(input, ranges) do
    ranges
    |> Enum.map(&{extend_whitespace(&1, input), ""})
    |> merge_deletes()
    |> Enum.sort_by(fn {{start, _stop}, _text} -> -start end)
    |> Enum.reduce(input, fn {{start, stop}, _text}, acc ->
      binary_part(acc, 0, start) <> binary_part(acc, stop, byte_size(acc) - stop)
    end)
  end

  # A deletion swallows the whitespace run after it (so neighbors don't end
  # up double-spaced); at end of input it swallows the run before it instead.
  defp extend_whitespace({start, stop}, input) do
    size = byte_size(input)
    stop = advance_ws(input, stop, size)
    start = if stop == size, do: retreat_ws(input, start), else: start
    {start, stop}
  end

  defp advance_ws(input, pos, size) when pos < size do
    if :binary.at(input, pos) in [?\s, ?\t, ?\n, ?\r],
      do: advance_ws(input, pos + 1, size),
      else: pos
  end

  defp advance_ws(_input, pos, _size), do: pos

  defp retreat_ws(input, pos) when pos > 0 do
    if :binary.at(input, pos - 1) in [?\s, ?\t, ?\n, ?\r],
      do: retreat_ws(input, pos - 1),
      else: pos
  end

  defp retreat_ws(_input, pos), do: pos

  # Adjacent deletions can overlap through their swallowed "and"/whitespace.
  defp merge_deletes(deletes) do
    deletes
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
    |> Enum.reduce([], fn
      {start, stop}, [{prev_start, prev_stop} | rest] when start <= prev_stop ->
        [{prev_start, max(stop, prev_stop)} | rest]

      range, acc ->
        [range | acc]
    end)
    |> Enum.map(&{&1, ""})
  end
end
