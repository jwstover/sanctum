defmodule Sanctum.Games.Actions.AltArtGalleryFacets do
  @moduledoc """
  Run module for `CardAlt :gallery_facets`: the artists, creator handles and
  target cards that occur on gallery alts, sorted, for the alt-art gallery's
  facet pickers. Reads through `:gallery`, so only alts in `:published` sets
  count — never a private or unlisted one, admins included.

  `cards` is a list of `%{id, name}` maps; the name carries the card code so
  same-named printings (two "Spider-Man" identities) stay distinguishable.
  """

  use Ash.Resource.Actions.Implementation

  alias Sanctum.Games.CardAlt

  @impl true
  def run(_input, _opts, context) do
    opts = Ash.Context.to_opts(context)

    CardAlt
    |> Ash.Query.for_read(:gallery, %{}, opts)
    |> Ash.Query.select([:artist, :creator_id, :card_id])
    |> Ash.Query.load([card: [:primary_side], creator: [:username]], strict?: true)
    |> Ash.read(opts)
    |> case do
      {:ok, alts} -> {:ok, facets(alts)}
      {:error, error} -> {:error, error}
    end
  end

  defp facets(alts) do
    %{
      artists:
        alts
        |> Enum.map(& &1.artist)
        |> Enum.reject(&(&1 in [nil, ""]))
        |> sorted_uniq(),
      creators:
        alts
        |> Enum.map(&(&1.creator && &1.creator.username))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&to_string/1)
        |> sorted_uniq(),
      cards:
        alts
        |> Enum.map(& &1.card)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(& &1.id)
        |> Enum.map(&%{id: &1.id, name: card_label(&1)})
        |> Enum.sort_by(&String.downcase(&1.name))
    }
  end

  defp card_label(%{primary_side: %{name: name}, code: code}) when is_binary(name),
    do: "#{name} (#{code})"

  defp card_label(%{code: code}), do: code

  defp sorted_uniq(values), do: values |> Enum.uniq() |> Enum.sort_by(&String.downcase/1)
end
