defmodule Sanctum.Games.Changes.CreateGameVillian do
  @moduledoc false

  alias Ash.Changeset

  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    case Changeset.fetch_attribute(changeset, :scenario_id) do
      {:ok, scenario_id} when is_binary(scenario_id) ->
        %{villains: [villian_card | _]} =
          Sanctum.Games.get_scenario!(scenario_id, load: [villains: [:primary_side]])

        side = villian_card.primary_side

        attrs = %{
          card_id: villian_card.id,
          health: side && side.health,
          max_health: side && side.health,
          attack: side && side.attack,
          scheme: side && side.scheme
        }

        Ash.Changeset.manage_relationship(changeset, :game_villian, attrs, type: :create)

      _ ->
        changeset
    end
  end
end
