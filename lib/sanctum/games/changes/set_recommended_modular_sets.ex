defmodule Sanctum.Games.Changes.SetRecommendedModularSets do
  @moduledoc false

  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    Ash.Changeset.fetch_attribute(changeset, :scenario_id)
    |> case do
      {:ok, scenario_id} when is_binary(scenario_id) ->
        scenario = Sanctum.Games.get_scenario!(scenario_id)

        Ash.Changeset.change_attribute(
          changeset,
          :modular_sets,
          scenario.recommended_modular_sets
        )

      _ ->
        changeset
    end
  end
end
