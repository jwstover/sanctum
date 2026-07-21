defmodule Sanctum.Search.Diagnostic do
  @moduledoc """
  A parse- or compile-time problem with a search query, pointing back at the
  offending span of the input.

  Diagnostics are advisory: the query still compiles and runs with the
  problematic part dropped (or, for a bad value on a known field, matching
  nothing) so partially-typed input never blanks the results abruptly.
  """

  defstruct [:severity, :code, :message, :start, :length]

  @type code ::
          :incomplete_clause
          | :unknown_field
          | :unsupported_operator
          | :invalid_value
          | :stray_token
          | :unclosed_paren
          | :misplaced_scope
          | :unknown_type

  @type t :: %__MODULE__{
          severity: :warning | :error,
          code: code(),
          message: String.t(),
          start: non_neg_integer(),
          length: non_neg_integer()
        }

  def new(severity, code, message, start, length) do
    %__MODULE__{severity: severity, code: code, message: message, start: start, length: length}
  end
end
