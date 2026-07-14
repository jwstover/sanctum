defmodule Sanctum.Repo.Migrations.ReclassifyPoolOwnershipAsAspect do
  @moduledoc """
  Data migration: reclassify existing 'Pool cards.

  'Pool was previously modeled as a CardOwnership value, so 'Pool cards synced
  as `ownership: "pool", aspect: NULL`. It is now a player aspect (see
  fix/pool-is-an-aspect), and `:pool` is no longer a valid CardOwnership. Any
  row still holding `ownership = 'pool'` fails to load through Ash, which breaks
  reads and — because the catalog sync's find-existing-side lookup then errors
  instead of matching — makes re-sync raise a duplicate-side constraint.

  Rewrite those rows to the new classification (`ownership: "player",
  aspect: "pool"`), matching exactly what the current MarvelCDB sync writes.

  This is a hand-written data migration (a deliberate exception to the
  "migrations are managed by ash.codegen" rule).
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE card_sides
    SET ownership = 'player', aspect = 'pool', updated_at = now()
    WHERE ownership = 'pool'
    """)
  end

  def down do
    # Reverses the reclassification. Only affects rows that carry the 'pool
    # aspect on the player pool, which is precisely the set rewritten in `up`.
    execute("""
    UPDATE card_sides
    SET ownership = 'pool', aspect = NULL, updated_at = now()
    WHERE ownership = 'player' AND aspect = 'pool'
    """)
  end
end
