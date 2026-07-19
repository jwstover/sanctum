defmodule Sanctum.Repo.Migrations.MergeDuplicateHeroVersions do
  @moduledoc """
  Data migration: collapse per-set duplicate Hero rows into one canonical row.

  The Hero upsert identity was `[:base_code, :set]`, but Ironheart's three
  suit versions are three separate hero-sided cards (base codes 29001/29002/
  29003) in the one `ironheart` set — card sync and deck import minted a Hero
  row per version, so she counted as up to three heroes in stats, the deck
  browser's hero filter, and the admin health snapshot.

  Keep each set's lowest-base_code row (the starting suit — the same pick
  `MarvelCdb.canonical_hero_card/1` now makes), repoint decks at it, and
  delete the rest. Must run before the follow-up migration that narrows the
  heroes unique index to `set` alone.

  Hand-written data migration (a deliberate exception to the
  "migrations are managed by ash.codegen" rule).
  """

  use Ecto.Migration

  def up do
    execute("""
    WITH canonical AS (
      SELECT DISTINCT ON (set) id, set
      FROM heroes
      WHERE set IS NOT NULL
      ORDER BY set, base_code
    )
    UPDATE decks d
    SET hero_id = c.id
    FROM heroes h
    JOIN canonical c ON c.set = h.set
    WHERE d.hero_id = h.id AND h.id <> c.id
    """)

    execute("""
    WITH canonical AS (
      SELECT DISTINCT ON (set) id, set
      FROM heroes
      WHERE set IS NOT NULL
      ORDER BY set, base_code
    )
    DELETE FROM heroes h
    USING canonical c
    WHERE c.set = h.set AND h.id <> c.id
    """)
  end

  def down do
    # No-op: the merged state (one Hero per set, decks on the canonical row)
    # is exactly what the canonicalized creation paths now write. Recreating
    # the duplicate rows would reintroduce the double-counting this removes.
    :ok
  end
end
