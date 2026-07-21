defmodule Sanctum.Games.Changes.GenerateCustomCode do
  @moduledoc """
  Mints codes for a custom (homebrew) card and normalizes its side maps.

  Custom codes are `custom-<uuid>` — outside MarvelCDB's numeric space, so
  they can never collide with (or be captured by) a catalog-sync upsert, and
  the existing unique identities keep working unchanged. Sides follow the
  official convention: `<code>a`/`<code>b`, `side_identifier` "a"/"b", the
  first side is primary.

  Each side map needs at least `image_url` — the image is the card. `name`
  falls back to a `filename`-derived title, then "Untitled"; everything else
  stays optional forever.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Sanctum.Games.CustomCode

  @impl true
  def change(changeset, _opts, _context) do
    code = CustomCode.mint()

    sides =
      changeset
      |> Changeset.get_argument(:card_sides)
      |> List.wrap()

    case Enum.find_index(sides, &(blank?(fetch(&1, :image_url)) and is_nil(fetch(&1, :id)))) do
      nil ->
        changeset
        |> Changeset.force_change_attribute(:code, code)
        |> Changeset.force_change_attribute(:base_code, code)
        |> Changeset.force_change_attribute(:is_multi_sided, length(sides) > 1)
        |> Changeset.set_argument(:card_sides, build_sides(sides, code))

      index ->
        Changeset.add_error(changeset,
          field: :card_sides,
          message: "side #{index + 1} is missing an image — the image is the card"
        )
    end
  end

  defp build_sides(sides, code) do
    sides
    |> Enum.zip(CustomCode.side_letters())
    |> Enum.map(fn {side, letter} ->
      normalized = Map.new(side, fn {key, value} -> {to_atom_key(key), value} end)

      normalized
      |> Map.delete(:filename)
      |> Map.put(:code, CustomCode.side_code(code, letter))
      |> Map.put(:side_identifier, letter)
      |> Map.put(:is_primary_side, letter == "a")
      |> Map.put(:name, side_name(normalized))
    end)
  end

  defp side_name(side) do
    name = side[:name]
    if blank?(name), do: default_name(side), else: name
  end

  defp default_name(side) do
    case fetch(side, :filename) do
      filename when is_binary(filename) and filename != "" ->
        filename
        |> Path.rootname()
        |> String.replace(~r/[-_]+/, " ")
        |> String.trim()
        |> title_case()

      _no_filename ->
        "Untitled"
    end
  end

  defp title_case(""), do: "Untitled"

  defp title_case(name) do
    name
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp fetch(side, key), do: side[key] || side[to_string(key)]

  defp to_atom_key(key) when is_atom(key), do: key
  defp to_atom_key(key) when is_binary(key), do: String.to_existing_atom(key)

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false
end
