defmodule Sanctum.Games.Changes.SetRecommendedModularSets do
  @moduledoc false

  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    Ash.Changeset.fetch_attribute(changeset, :scenario_id)
    |> case do
      {:ok, scenario_id} when is_binary(scenario_id) ->
        scenario = Sanctum.Games.get_scenario!(scenario_id, load: [:modular_sets])

        # Game.modular_sets stays a code snapshot on purpose, because
        # CreateGameEncounterDeck.get_modular_set_cards/1 filters
        # Card.set in ^modular_sets.
        Ash.Changeset.change_attribute(
          changeset,
          :modular_sets,
          Enum.map(scenario.modular_sets, & &1.code)
        )

      _ ->
        changeset
    end
  end
end
