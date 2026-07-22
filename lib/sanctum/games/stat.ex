defmodule Sanctum.Games.Stat do
  @moduledoc """
  A card stat as four independent axes:

    * `value` — the printed number (nil when the stat is absent)
    * `star` — a ★ effect relates to this stat (co-occurs with `value`)
    * `scaling` — how the value scales with player count (`:flat`, `:per_player`,
      `:per_group`)
    * `consequential` — an ally's consequential damage for this stat (stars taken
      when it attacks/thwarts/defends; nil when the stat carries no cost)

  Used for attack, thwart, defense, recover, health, and the scheme threats,
  stored inline as a jsonb column per stat. A card with no such stat stores the
  whole attribute as nil.

  A custom `Ash.Type` (not an embedded resource) so it behaves as a plain
  attribute in forms while still loading into a struct. `cast_input` accepts a
  bare number (treated as the value, flat/no-star) or a full map — so the sync,
  fixtures, and simple form inputs can all provide a value directly.
  """

  use Ash.Type

  defstruct value: nil, star: false, scaling: :flat, consequential: nil

  @doc """
  The bare value for a number input editing this stat. Tolerates the raw
  string/integer/map params a form round-trips between validates.
  """
  def input_value(%__MODULE__{value: value}), do: value
  def input_value(%{} = params), do: fetch(params, :value)
  def input_value(value) when is_integer(value) or is_binary(value), do: value
  def input_value(_), do: nil

  @doc "Whether the ★ box should be checked; tolerates form params."
  def input_star(%__MODULE__{star: star}), do: star
  def input_star(%{} = params), do: truthy(fetch(params, :star))
  def input_star(_), do: false

  @doc "The consequential-damage input value; tolerates form params."
  def input_consequential(%__MODULE__{consequential: consequential}), do: consequential
  def input_consequential(%{} = params), do: fetch(params, :consequential)
  def input_consequential(_), do: nil

  @doc "The scaling select value; tolerates form params."
  def input_scaling(%__MODULE__{scaling: scaling}), do: scaling
  def input_scaling(%{} = params), do: to_scaling(fetch(params, :scaling))
  def input_scaling(_), do: :flat

  @scalings [:flat, :per_player, :per_group]

  @impl true
  def storage_type(_constraints), do: :map

  @impl true
  def cast_input(nil, _), do: {:ok, nil}
  def cast_input(%__MODULE__{} = stat, _), do: {:ok, stat}
  def cast_input(value, _) when is_integer(value), do: {:ok, %__MODULE__{value: value}}

  def cast_input(value, _) when is_binary(value) do
    case String.trim(value) do
      "" ->
        {:ok, nil}

      trimmed ->
        case Integer.parse(trimmed) do
          {int, ""} -> {:ok, %__MODULE__{value: int}}
          _ -> :error
        end
    end
  end

  # An all-default map (blank form inputs) collapses to nil so an untouched
  # stat stays "absent" rather than becoming an empty struct.
  def cast_input(%{} = map, _) do
    case from_map(map) do
      %__MODULE__{value: nil, star: false, scaling: :flat, consequential: nil} -> {:ok, nil}
      stat -> {:ok, stat}
    end
  end

  def cast_input(_, _), do: :error

  @impl true
  def cast_stored(nil, _), do: {:ok, nil}
  def cast_stored(%{} = map, _), do: {:ok, from_map(map)}
  def cast_stored(_, _), do: :error

  @impl true
  def dump_to_native(nil, _), do: {:ok, nil}

  def dump_to_native(%__MODULE__{} = stat, _) do
    {:ok,
     %{
       "value" => stat.value,
       "star" => stat.star,
       "scaling" => to_string(stat.scaling),
       "consequential" => stat.consequential
     }}
  end

  def dump_to_native(_, _), do: :error

  defp from_map(map) do
    %__MODULE__{
      value: to_int(fetch(map, :value)),
      star: truthy(fetch(map, :star)),
      scaling: to_scaling(fetch(map, :scaling)),
      consequential: to_int(fetch(map, :consequential))
    }
  end

  defp fetch(map, key), do: Map.get(map, key, Map.get(map, to_string(key)))

  defp to_int(nil), do: nil
  defp to_int(int) when is_integer(int), do: int

  defp to_int(str) when is_binary(str) do
    case Integer.parse(String.trim(str)) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp truthy(true), do: true
  defp truthy("true"), do: true
  defp truthy("on"), do: true
  defp truthy(_), do: false

  defp to_scaling(scaling) when scaling in @scalings, do: scaling
  defp to_scaling("per_player"), do: :per_player
  defp to_scaling("per_group"), do: :per_group
  defp to_scaling(_), do: :flat
end
