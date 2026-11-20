defmodule Sanctum.Homebrew.Actions.DirectoryFacets do
  @moduledoc """
  Run module for `HomebrewSet :directory_facets`: the creator handles and
  tags that occur on published sets, sorted, for the directory's facet
  pickers. Reads through `:directory`, so only `:published` sets count —
  never a private or unlisted one, admins included.
  """

  use Ash.Resource.Actions.Implementation

  alias Sanctum.Homebrew.HomebrewSet

  require Ash.Query

  @impl true
  def run(_input, _opts, context) do
    opts = Ash.Context.to_opts(context)

    HomebrewSet
    |> Ash.Query.for_read(:directory, %{}, opts)
    |> Ash.Query.select([:tags, :creator_id])
    |> Ash.Query.load(creator: [:username])
    |> Ash.read(opts)
    |> case do
      {:ok, sets} ->
        {:ok,
         %{
           creators:
             sets
             |> Enum.map(&(&1.creator && &1.creator.username))
             |> Enum.reject(&is_nil/1)
             |> Enum.map(&to_string/1)
             |> Enum.uniq()
             |> Enum.sort_by(&String.downcase/1),
           tags:
             sets
             |> Enum.flat_map(&(&1.tags || []))
             |> Enum.uniq()
             |> Enum.sort_by(&String.downcase/1)
         }}

      {:error, error} ->
        {:error, error}
    end
  end
end
