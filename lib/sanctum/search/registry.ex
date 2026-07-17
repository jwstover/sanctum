defmodule Sanctum.Search.Registry do
  @moduledoc """
  Behaviour + helpers for a search-field registry (one per searchable surface:
  `Sanctum.Search.CardFields`, `Sanctum.Search.DeckFields`).

  A registry enumerates the queryable fields and provides the bare-word
  fallback filter (what a plain `spider` term means on that surface). The
  registry is the security boundary: the compiler only ever builds filters
  for fields a registry explicitly defines.
  """

  alias Sanctum.Search.Field

  @callback fields() :: [Field.t()]
  @callback bare_word(String.t()) :: term()

  @doc "Find a field by name or alias (case-insensitive, `-` treated as `_`)."
  @spec lookup(module(), String.t()) :: Field.t() | nil
  def lookup(registry, name) do
    n = normalize(name)
    Enum.find(registry.fields(), fn f -> n == f.name or n in f.aliases end)
  end

  @doc "Best did-you-mean suggestion for an unknown field name, or nil."
  @spec suggest(module(), String.t()) :: String.t() | nil
  def suggest(registry, name) do
    n = normalize(name)

    registry.fields()
    |> Enum.map(& &1.name)
    |> Enum.map(&{&1, String.jaro_distance(n, &1)})
    |> Enum.max_by(fn {_, score} -> score end, fn -> {nil, 0.0} end)
    |> case do
      {candidate, score} when score >= 0.7 -> candidate
      _ -> nil
    end
  end

  @doc "Normalize user-typed field/value text for matching."
  @spec normalize(String.t()) :: String.t()
  def normalize(text) do
    text
    |> String.downcase()
    |> String.replace(["-", " "], "_")
  end
end
