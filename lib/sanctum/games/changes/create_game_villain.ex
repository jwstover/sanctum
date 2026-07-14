defmodule Sanctum.Games.Changes.CreateGameVillain do
  @moduledoc false

  alias Ash.Changeset

  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    case Changeset.fetch_attribute(changeset, :scenario_id) do
      {:ok, scenario_id} when is_binary(scenario_id) ->
        %{villains: [villain_card | _]} =
          Sanctum.Games.get_scenario!(scenario_id, load: [villains: [:primary_side]])

        side = villain_card.primary_side

        # Find or create the Villain resource based on the card's villain side
        {:ok, villain} =
          if side && side.type == :villain do
            Sanctum.Villains.find_or_create_villain(%{
              villain_name: side.name,
              set: villain_card.set
            })
          else
            {:error, "Invalid villain card"}
          end

        health = side && stat_value(side.health)

        attrs = %{
          villain_id: villain.id,
          card_id: villain_card.id,
          active_side_id: side.id,
          health: health,
          max_health: health,
          attack: side && stat_value(side.attack),
          scheme: side && side.scheme
        }

        Ash.Changeset.manage_relationship(changeset, :game_villain, attrs, type: :create)

      _ ->
        changeset
    end
  end

  defp stat_value(nil), do: nil
  defp stat_value(%{value: value}), do: value
end
