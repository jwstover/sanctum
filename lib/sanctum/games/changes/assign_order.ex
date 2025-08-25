defmodule Sanctum.Games.Changes.AssignOrder do
  @moduledoc """
  Assigns the next available `order` for a card within its `game_player_id`.

  - Uses gapped integers (increments of 10).
  - Skips assignment if `order` is already provided in the changeset.
  """

  use Ash.Resource.Change
  import Ecto.Query

  def change(changeset, _opts, _context) do
    # Only assign if no `order` was explicitly set
    if Ash.Changeset.changing_attribute?(changeset, :order) do
      changeset
    else
      game_player_id = Ash.Changeset.get_attribute(changeset, :game_player_id)
      game_encounter_deck_id = Ash.Changeset.get_attribute(changeset, :game_encounter_deck_id)

      where = if game_encounter_deck_id do
        [game_encounter_deck_id: game_encounter_deck_id]
      else
        [game_player_id: game_player_id]
      end

      max_order =
        Sanctum.Repo.one(
          from c in changeset.resource,
            where: ^where,
            select: max(c.order)
        ) || 0

      Ash.Changeset.force_change_attribute(changeset, :order, max_order + 10)
    end
  end
end
