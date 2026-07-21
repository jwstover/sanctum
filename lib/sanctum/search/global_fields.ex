defmodule Sanctum.Search.GlobalFields do
  @moduledoc """
  Suggest-only registry for the global search bar: the reserved `in:` type
  qualifier plus the union of every type registry's fields, merged by
  canonical name (aliases/values/operators unioned, data-driven value funs
  composed).

  This registry is never compiled against — `Sanctum.Search.Global` always
  compiles per type registry after extracting the `in:` scope — so
  `bare_word/1` returns nil and merged `build` functions are never invoked.
  It only exists to feed `Sanctum.Search.Suggest` when the query isn't scoped
  to a single type.
  """

  @behaviour Sanctum.Search.Registry

  alias Sanctum.Search.{Field, Global}

  # Fields available on at most this many types get their hint suffixed with
  # the surfaces they apply to ("cost" → "cards"); beyond that the field is
  # effectively universal and the suffix is noise.
  @surface_hint_max 3

  @impl true
  def bare_word(_value), do: nil

  @impl true
  def fields do
    [in_field() | union_fields()]
  end

  defp in_field do
    %Field{
      name: "in",
      kind: :enum,
      values: Global.type_values(),
      ops: [:eq],
      example: "in:cards",
      hint: "limit results to one type",
      build: fn _op, _value -> {:error, ~s(the "in" filter is handled before compilation)} end
    }
  end

  defp union_fields do
    tagged =
      Enum.flat_map(Global.types(), fn %{key: key, registry: registry} ->
        Enum.map(registry.fields(), &{key, &1})
      end)

    # First-seen order is autocomplete priority, so the card fields (the
    # biggest surface) lead, matching the pool's suggestions.
    tagged
    |> Enum.map(fn {_key, field} -> field.name end)
    |> Enum.uniq()
    |> Enum.map(fn name ->
      tagged
      |> Enum.filter(fn {_key, field} -> field.name == name end)
      |> merge()
    end)
  end

  defp merge([{_key, first} | _] = group) do
    keys = group |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    fields = Enum.map(group, &elem(&1, 1))

    %Field{
      first
      | aliases: fields |> Enum.flat_map(& &1.aliases) |> Enum.uniq(),
        values: fields |> Enum.flat_map(& &1.values) |> Enum.uniq(),
        values_fun: fields |> Enum.map(& &1.values_fun) |> compose_values_funs(),
        ops: fields |> Enum.flat_map(& &1.ops) |> Enum.uniq(),
        hint: scoped_hint(first, keys)
    }
  end

  defp scoped_hint(%Field{} = field, keys) when length(keys) <= @surface_hint_max do
    [field.hint || field.example, Enum.map_join(keys, " · ", &surface_label/1)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" — ")
  end

  defp scoped_hint(%Field{} = field, _keys), do: field.hint

  defp surface_label(:card_sets), do: "sets"
  defp surface_label(key), do: to_string(key)

  defp compose_values_funs(funs) do
    case Enum.reject(funs, &is_nil/1) do
      [] -> nil
      [one] -> one
      many -> fn -> many |> Enum.flat_map(& &1.()) |> Enum.uniq() end
    end
  end
end
