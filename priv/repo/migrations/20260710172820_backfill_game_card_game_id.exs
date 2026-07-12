defmodule Sanctum.Repo.Migrations.BackfillGameCardGameId do
  @moduledoc """
  Data migration: backfill game_cards.game_id from each card's parent
  (game_player or game_encounter_deck) so the column can be made required.

  This is a hand-written data migration (a deliberate exception to the
  "migrations are managed by ash.codegen" rule).
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE game_cards
    SET game_id = gp.game_id
    FROM game_players gp
    WHERE game_cards.game_player_id = gp.id
      AND game_cards.game_id IS NULL
    """)

    execute("""
    UPDATE game_cards
    SET game_id = ged.game_id
    FROM game_encounter_decks ged
    WHERE game_cards.game_encounter_deck_id = ged.id
      AND game_cards.game_id IS NULL
    """)
  end

  def down do
    # No-op: backfilling game_id is not destructive and does not need to be undone.
    execute("SELECT 1")
  end
end
