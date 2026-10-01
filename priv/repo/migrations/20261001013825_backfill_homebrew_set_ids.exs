defmodule Sanctum.Repo.Migrations.BackfillHomebrewSetIds do
  @moduledoc """
  Data migration: give every existing homebrew project a set (inheriting its
  name/visibility/maturity/tags/creator) and point that project's custom
  cards, alts and aspects at its oldest set, so the origin<->set check
  constraint can be added.

  This is a hand-written data migration (a deliberate exception to the
  "migrations are managed by ash.codegen" rule).
  """

  use Ecto.Migration

  @tables ~w(cards card_alts aspects)

  def up do
    execute("""
    INSERT INTO homebrew_sets
      (id, name, visibility, maturity, tags, creator_id, homebrew_project_id)
    SELECT uuid_generate_v7(), p.name, p.visibility, p.maturity, p.tags, p.creator_id, p.id
    FROM homebrew_projects p
    WHERE NOT EXISTS (SELECT 1 FROM homebrew_sets s WHERE s.homebrew_project_id = p.id)
    """)

    for table <- @tables do
      execute("""
      UPDATE #{table}
      SET homebrew_set_id = s.id
      FROM (
        SELECT DISTINCT ON (homebrew_project_id) id, homebrew_project_id
        FROM homebrew_sets
        ORDER BY homebrew_project_id, inserted_at, id
      ) s
      WHERE #{table}.homebrew_project_id = s.homebrew_project_id
        AND #{table}.homebrew_project_id IS NOT NULL
        AND #{table}.homebrew_set_id IS NULL
      """)
    end
  end

  def down do
    # No-op: backfilled sets and links are not destructive and need no undoing.
    execute("SELECT 1")
  end
end
