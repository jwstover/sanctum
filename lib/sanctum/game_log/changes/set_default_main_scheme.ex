defmodule Sanctum.GameLog.Changes.SetDefaultMainScheme do
  @moduledoc """
  Fills `main_scheme_id` when the scenario has exactly one main scheme and the
  caller didn't supply one.
  """
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    with nil <- Ash.Changeset.get_attribute(changeset, :main_scheme_id),
         {:ok, scenario_id} when is_binary(scenario_id) <-
           Ash.Changeset.fetch_attribute(changeset, :scenario_id),
         %{main_schemes: [only]} <-
           Sanctum.Games.get_scenario!(scenario_id, load: [:main_schemes]) do
      Ash.Changeset.change_attribute(changeset, :main_scheme_id, only.id)
    else
      _ -> changeset
    end
  end
end
