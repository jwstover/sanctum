defmodule Sanctum.Search.Lexer do
  @moduledoc """
  Tokenizes a search query string into `Sanctum.Search.Token`s.

  The lexer never fails: every character belongs to some token (unmatched
  input degrades to `:word` tokens), so partially-typed queries still
  tokenize and the parser can decide what to keep. Spans are byte offsets
  into the original input.
  """

  import NimbleParsec

  alias Sanctum.Search.Token

  # Characters that terminate a word. Everything else — including `-`, `'`,
  # `.`, `,`, `/` — is word material so card names like "Spider-Man",
  # "S.H.I.E.L.D.", and "SP//dr" survive as single tokens.
  @word_stops [?\s, ?\t, ?\n, ?\r, ?", ?(, ?), ?|, ?:, ?<, ?>, ?=, ?!]

  # `mark` pushes `{[], current_byte_offset}` into the results without
  # consuming input — used as start/end markers around each token matcher.
  mark = byte_offset(empty())

  token = fn kind, matcher ->
    mark
    |> concat(matcher)
    |> concat(mark)
    |> post_traverse({:emit, [kind]})
  end

  ws = ignore(ascii_string([?\s, ?\t, ?\n, ?\r], min: 1))

  quoted =
    token.(
      :string,
      ignore(string(~s(")))
      |> utf8_string([not: ?"], min: 0)
      |> optional(ignore(string(~s("))))
    )

  op =
    token.(
      :op,
      choice([
        string("<="),
        string(">="),
        string("!="),
        string("<"),
        string(">"),
        string("="),
        string(":"),
        string("!")
      ])
    )

  lparen = token.(:lparen, string("("))
  rparen = token.(:rparen, string(")"))
  pipe = token.(:pipe, string("|"))

  # `-` negates the following term (Scryfall-style). Only lexed as negation
  # when it starts a token and something follows; a hyphen inside a word
  # ("spider-man") is consumed by the word matcher instead.
  neg =
    token.(
      :neg,
      string("-") |> lookahead(utf8_char(not: ?\s, not: ?\t, not: ?\n, not: ?\r))
    )

  word = token.(:word, utf8_string(Enum.map(@word_stops, &{:not, &1}), min: 1))

  any_token = choice([quoted, op, lparen, rparen, pipe, neg, word])

  defparsecp(:do_tokenize, repeat(choice([ws, any_token])) |> eos())

  @doc "Tokenize `input`. Always succeeds."
  @spec tokenize(String.t()) :: [Token.t()]
  def tokenize(input) when is_binary(input) do
    {:ok, tokens, "", _context, _line, _offset} = do_tokenize(input)
    tokens
  end

  # Results between the two offset markers form the token value; ignored
  # pieces (quote marks) contribute to the span but not the value.
  defp emit(rest, args, context, _line, _offset, kind) do
    [{[], end_off} | rest_args] = args
    {value_parts, [{[], start_off}]} = Enum.split(rest_args, length(rest_args) - 1)

    value =
      value_parts
      |> Enum.reverse()
      |> Enum.map_join("", &to_string/1)

    token = %Token{kind: kind, value: value, start: start_off, length: end_off - start_off}
    {rest, [token], context}
  end
end
