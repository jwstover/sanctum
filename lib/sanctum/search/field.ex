defmodule Sanctum.Search.Field do
  @moduledoc """
  One queryable field in a search registry.

  * `name` — canonical field name as typed by users (`"cost"`)
  * `aliases` — accepted shorthands (`["c"]`, MarvelCDB-style letters)
  * `kind` — drives autocomplete rendering and docs: `:text | :integer |
    :stat | :enum | :boolean | :flag`
  * `values` — the statically completable values (enum fields and flags)
  * `values_fun` — optional zero-arity fun returning data-driven completable
    values (distinct traits, hero names, …); called lazily at suggest time
    and expected to be cheap (see `Sanctum.Search.Values` / `ValueCache`)
  * `ops` — operators this field accepts (`:eq :neq :lt :gt :lte :gte`)
  * `build` — `(op, raw_value) -> {:ok, ash_expr} | {:error, message}`;
    validation (enum coercion, integer parsing) happens here
  * `example` / `hint` — shown in autocomplete and the syntax help
  """

  @enforce_keys [:name, :kind, :build]
  defstruct [
    :name,
    :kind,
    :build,
    :example,
    :hint,
    :values_fun,
    aliases: [],
    values: [],
    ops: [:eq, :neq]
  ]

  @type op :: :eq | :neq | :lt | :gt | :lte | :gte

  @doc """
  Builds the common plain text field shape — `:text` kind, no aliases or
  completable values, just an example/hint and a build function.
  """
  def text(name, example, hint, build) do
    %__MODULE__{name: name, kind: :text, example: example, hint: hint, build: build}
  end

  @type t :: %__MODULE__{
          name: String.t(),
          kind: :text | :integer | :stat | :enum | :boolean | :flag,
          build: (op(), String.t() -> {:ok, term()} | {:error, String.t()}),
          example: String.t() | nil,
          hint: String.t() | nil,
          values_fun: (-> [String.t()]) | nil,
          aliases: [String.t()],
          values: [String.t()],
          ops: [op()]
        }
end
