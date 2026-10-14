defmodule Sanctum.GameLog.Changes.SetVillainFromScenario do
  @moduledoc """
  Derives `villain_id` from the chosen scenario's villain card, exactly like
  `Sanctum.Games.Changes.CreateGameVillain` does for the live game. The user
  never picks a villain directly — it's implied by the scenario.
  """
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    case Ash.Changeset.fetch_attribute(changeset, :scenario_id) do
      {:ok, scenario_id} when is_binary(scenario_id) ->
        %{villains: [villain_card | _]} =
          Sanctum.Games.get_scenario!(scenario_id, load: [villains: [:primary_side]])

        side = villain_card.primary_side

        {:ok, villain} =
          Sanctum.Villains.find_or_create_villain(%{
            villain_name: side.name,
            set: villain_card.set
          })

        Ash.Changeset.change_attribute(changeset, :villain_id, villain.id)

      _ ->
        changeset
    end
  end
end
