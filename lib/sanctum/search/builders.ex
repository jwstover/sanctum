defmodule Sanctum.Search.Builders do
  @moduledoc """
  Shared helpers for registry `build` functions: value coercion (integers,
  booleans, enums with did-you-mean) and dynamic Ash expression construction
  (comparisons on plain columns and on jsonb `Sanctum.Games.Stat` values).
  """

  import Ash.Expr

  alias Sanctum.Search.Registry

  # -- expression builders -----------------------------------------------------

  @doc "Comparison against a plain attribute (or any pinned expression)."
  def cmp(target, :eq, value), do: expr(^target == ^value)
  def cmp(target, :neq, value), do: expr(^target != ^value)
  def cmp(target, :lt, value), do: expr(^target < ^value)
  def cmp(target, :gt, value), do: expr(^target > ^value)
  def cmp(target, :lte, value), do: expr(^target <= ^value)
  def cmp(target, :gte, value), do: expr(^target >= ^value)

  @doc """
  Comparison against the printed number of a `Sanctum.Games.Stat` jsonb
  attribute. Sides where the stat (or its value — a `⭐`/`X` printing) is
  absent compare as SQL NULL and drop out of the results.
  """
  def stat_cmp(attr, op, value) do
    cmp(expr(fragment("(? ->> 'value')::integer", ^ref(attr))), op, value)
  end

  @doc "Case-insensitive substring match, with ILIKE wildcards escaped."
  def contains(target, raw) do
    expr(ilike(^target, ^pattern(raw)))
  end

  @doc "`%…%` ILIKE pattern for user input, escaping `%`, `_`, and `\\`."
  def pattern(raw) do
    escaped =
      raw
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    "%" <> escaped <> "%"
  end

  # -- value coercion ----------------------------------------------------------

  @doc "Strictly parse an integer value."
  def parse_int(raw) do
    case Integer.parse(String.trim(raw)) do
      {n, ""} -> {:ok, n}
      _ -> {:error, ~s("#{raw}" is not a number)}
    end
  end

  @doc "Parse a boolean value (true/false/yes/no/1/0)."
  def parse_bool(raw) do
    case Registry.normalize(raw) do
      t when t in ["true", "yes", "1"] -> {:ok, true}
      f when f in ["false", "no", "0"] -> {:ok, false}
      _ -> {:error, ~s("#{raw}" should be true or false)}
    end
  end

  @doc """
  Coerce user input to one of `values` (atoms or strings): exact match first,
  then a unique-prefix match (`t:all` → `:ally`), otherwise an error with a
  did-you-mean suggestion when one is close enough. Returns the matched value
  as given in `values` — no atoms are created.
  """
  def coerce_enum(raw, values) do
    norm = Registry.normalize(raw)
    indexed = Enum.map(values, &{to_string(&1), &1})

    exact = List.keyfind(indexed, norm, 0)
    prefixed = Enum.filter(indexed, fn {s, _} -> String.starts_with?(s, norm) end)

    case {exact, prefixed} do
      {{_, value}, _} ->
        {:ok, value}

      {nil, [{_, value}]} when norm != "" ->
        {:ok, value}

      _ ->
        strings = Enum.map(indexed, &elem(&1, 0))
        {:error, ~s("#{raw}" doesn't match#{did_you_mean(norm, strings)})}
    end
  end

  defp did_you_mean(input, candidates) do
    candidates
    |> Enum.map(&{&1, String.jaro_distance(input, &1)})
    |> Enum.max_by(fn {_, score} -> score end, fn -> {nil, 0.0} end)
    |> case do
      {candidate, score} when score >= 0.6 -> ~s( — did you mean "#{candidate}"?)
      _ -> ""
    end
  end
end
