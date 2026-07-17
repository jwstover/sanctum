defmodule Sanctum.Search.Suggest do
  @moduledoc """
  Cursor-context-aware autocomplete for the search query language.

  Given the input string, the cursor position (in UTF-16 code units, as
  reported by the browser), and a field registry, returns the suggestions the
  query-input hook renders as a combobox:

      %{items: [%{label:, detail:, insert:, kind:}], start: s, length: l}

  `start`/`length` (UTF-16 units) are the span the accepted suggestion's
  `insert` text replaces — the token being completed, or a zero-length span
  at the cursor.

  Context rules:

    * at a bare/partial word → complete field names (insert `field:`)
    * after `field op` → complete the field's values (enums, flags, booleans)
    * inside a quoted string or after an unknown field → no suggestions
  """

  alias Sanctum.Search.{Field, Lexer, Registry, Token}

  @keywords ~w(or and not)

  @max_items 10

  @spec suggest(String.t(), non_neg_integer(), module()) :: map()
  def suggest(input, cursor_utf16, registry)
      when is_binary(input) and is_integer(cursor_utf16) do
    cursor = utf16_to_byte(input, max(cursor_utf16, 0))
    tokens = Lexer.tokenize(input)

    current = Enum.find(tokens, &(&1.start < cursor and cursor <= &1.start + &1.length))
    before = tokens |> Enum.take_while(&(&1.start + &1.length <= cursor)) |> Enum.reverse()

    {items, {start, len}} = suggestions(current, before, cursor, registry)

    %{
      items: Enum.take(items, @max_items),
      start: byte_to_utf16(input, start),
      length: byte_to_utf16(input, start + len) - byte_to_utf16(input, start)
    }
  end

  # -- context resolution ------------------------------------------------------

  # Cursor inside/at the end of a word: completing a value if the word follows
  # `field op`, otherwise completing a field name.
  defp suggestions(%Token{kind: :word} = word, before, _cursor, registry) do
    span = {word.start, word.length}

    # `before` only includes the word itself when the cursor sits at its end;
    # drop it either way to look at what precedes the word.
    prior =
      case before do
        [^word | rest] -> rest
        other -> other
      end

    case prior do
      [%Token{kind: :op} = op, %Token{kind: :word} = field_tok | _] ->
        {value_items(registry, field_tok, op, word.value), span}

      _ ->
        {field_items(registry, word.value), span}
    end
  end

  # Cursor at the end of an operator: complete the field's values.
  defp suggestions(%Token{kind: :op} = op, before, cursor, registry) do
    case before do
      [^op, %Token{kind: :word} = field_tok | _] ->
        {value_items(registry, field_tok, op, ""), {cursor, 0}}

      _ ->
        {[], {cursor, 0}}
    end
  end

  # No suggestions while typing a quoted phrase.
  defp suggestions(%Token{kind: :string}, _before, cursor, _registry), do: {[], {cursor, 0}}

  # Cursor in whitespace / at the ends of the input.
  defp suggestions(nil, before, cursor, registry) do
    case before do
      # `aspect:` then a space — still the value position.
      [%Token{kind: :op} = op, %Token{kind: :word} = field_tok | _] ->
        {value_items(registry, field_tok, op, ""), {cursor, 0}}

      _ ->
        {field_items(registry, ""), {cursor, 0}}
    end
  end

  defp suggestions(%Token{}, _before, cursor, _registry), do: {[], {cursor, 0}}

  # -- item builders -----------------------------------------------------------

  defp field_items(registry, prefix) do
    norm = Registry.normalize(prefix)

    fields =
      for field <- registry.fields(),
          match = matching_name(field, norm),
          do: %{
            label: match,
            detail: field_detail(field, match),
            insert: match <> ":",
            kind: "field"
          }

    keywords =
      for kw <- @keywords, norm != "", String.starts_with?(kw, norm) do
        %{label: kw, detail: "combine terms", insert: kw <> " ", kind: "keyword"}
      end

    fields ++ keywords
  end

  # The canonical name if it matches, otherwise a matching alias (shown as the
  # alias but described by the canonical name).
  defp matching_name(%Field{} = field, prefix) do
    cond do
      String.starts_with?(field.name, prefix) -> field.name
      match = Enum.find(field.aliases, &String.starts_with?(&1, prefix)) -> match
      true -> nil
    end
  end

  defp field_detail(%Field{} = field, shown_name) do
    base = field.hint || field.example

    if shown_name == field.name do
      base
    else
      String.trim("#{field.name} — #{base}")
    end
  end

  defp value_items(registry, %Token{value: field_name}, %Token{value: op}, prefix) do
    with %Field{} = field <- Registry.lookup(registry, field_name),
         true <- op_allowed?(field, op) do
      norm = Registry.normalize(prefix)

      for value <- field.values ++ dynamic_values(field),
          String.starts_with?(Registry.normalize(value), norm) do
        %{label: value, detail: nil, insert: quote_if_needed(value), kind: "value"}
      end
    else
      _ -> []
    end
  end

  defp dynamic_values(%Field{values_fun: nil}), do: []
  defp dynamic_values(%Field{values_fun: fun}), do: fun.()

  # Values containing word-breaking characters ("Accuser Corps",
  # "Black Widow") must be inserted as quoted phrases or the lexer would
  # split them into separate terms.
  defp quote_if_needed(value) do
    if String.match?(value, ~r/[\s"()|:<>=!]/) do
      ~s(") <> String.replace(value, ~s("), "") <> ~s(")
    else
      value
    end
  end

  defp op_allowed?(%Field{ops: ops}, op_text) do
    op =
      case op_text do
        ":" -> :eq
        "=" -> :eq
        "!=" -> :neq
        "!" -> :neq
        "<" -> :lt
        ">" -> :gt
        "<=" -> :lte
        ">=" -> :gte
      end

    op in ops
  end

  # -- UTF-16 <-> byte offset conversion ----------------------------------------
  # The browser reports cursor positions in UTF-16 code units; lexer spans are
  # byte offsets. Codepoints above 0xFFFF take two UTF-16 units.

  defp utf16_to_byte(input, units), do: u2b(input, units, 0)

  defp u2b(_rest, units, bytes) when units <= 0, do: bytes
  defp u2b(<<>>, _units, bytes), do: bytes

  defp u2b(<<cp::utf8, rest::binary>>, units, bytes) do
    u2b(rest, units - utf16_units(cp), bytes + byte_size(<<cp::utf8>>))
  end

  defp byte_to_utf16(input, target), do: b2u(input, target, 0, 0)

  defp b2u(_rest, target, bytes, units) when bytes >= target, do: units
  defp b2u(<<>>, _target, _bytes, units), do: units

  defp b2u(<<cp::utf8, rest::binary>>, target, bytes, units) do
    b2u(rest, target, bytes + byte_size(<<cp::utf8>>), units + utf16_units(cp))
  end

  defp utf16_units(cp) when cp > 0xFFFF, do: 2
  defp utf16_units(_cp), do: 1
end
