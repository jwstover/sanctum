defmodule Sanctum.Search.Token do
  @moduledoc """
  A single lexed token of a search query, carrying its source span so
  diagnostics and highlighting can point back at the original input.

  Kinds:

    * `:word` — an unquoted run of text (field names, values, bare search terms)
    * `:string` — a double-quoted phrase (quotes stripped from `value`)
    * `:op` — a comparison operator (`:` `=` `!=` `!` `<` `>` `<=` `>=`)
    * `:lparen` / `:rparen` — grouping
    * `:pipe` — value-level OR separator (`aspect:justice|leadership`)
    * `:neg` — a `-` negation prefix
  """

  defstruct [:kind, :value, :start, :length]

  @type kind :: :word | :string | :op | :lparen | :rparen | :pipe | :neg

  @type t :: %__MODULE__{
          kind: kind(),
          value: String.t(),
          start: non_neg_integer(),
          length: non_neg_integer()
        }
end
