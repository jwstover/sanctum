defmodule Sanctum.Homebrew.Actions.DeletionImpact do
  @moduledoc """
  Run module for `HomebrewSet :deletion_impact`: the blast radius of
  destroying a set, read as the actor through the shared `:subtree` walk.
  """

  use Ash.Resource.Actions.Implementation

  alias Sanctum.Homebrew.HomebrewSet

  require Ash.Query

  @impl true
  def run(input, _opts, context) do
    set_id = input.arguments.set_id

    HomebrewSet
    |> Ash.Query.for_read(:subtree, %{set_id: set_id}, Ash.Context.to_opts(context))
    |> Ash.Query.load([:card_count, :alt_count])
    |> Ash.Query.sort(:name)
    |> Ash.read(Ash.Context.to_opts(context))
    |> case do
      {:ok, []} ->
        {:error, Ash.Error.Query.NotFound.exception(resource: HomebrewSet, primary_key: set_id)}

      {:ok, sets} ->
        {:ok,
         %{
           descendant_set_count: length(sets) - 1,
           card_count: sets |> Enum.map(& &1.card_count) |> Enum.sum(),
           alt_count: sets |> Enum.map(& &1.alt_count) |> Enum.sum(),
           published_sets: for(%{visibility: :published, name: name} <- sets, do: name),
           deck_count: deck_count(Enum.map(sets, & &1.id))
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  # Decks are other users' (often private) data, so this is a system read
  # that only ever returns a count.
  defp deck_count(set_ids) do
    Sanctum.Decks.DeckCard
    |> Ash.Query.filter(card.homebrew_set_id in ^set_ids)
    |> Ash.Query.select([:deck_id])
    |> Ash.read!(authorize?: false)
    |> Enum.uniq_by(& &1.deck_id)
    |> length()
  end
end
