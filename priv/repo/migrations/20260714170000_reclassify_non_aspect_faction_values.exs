defmodule Sanctum.Repo.Migrations.ReclassifyNonAspectFactionValues do
  @moduledoc """
  Data migration: fix `card_sides.aspect` rows still holding ownership-only
  faction values.

  The faction split (`split_card_faction`) moved MarvelCDB's overloaded
  `faction_code` into two columns — `ownership` (which pool a card comes from)
  and `aspect` (the player aspects only). But it only *added* the `ownership`
  column; it never scrubbed the raw faction value out of `aspect`. Rows synced
  before the split kept ownership-only values there — "encounter" (~1,644) and
  "basic" (~329) — which are no longer valid `CardAspect` members.

  Any such row fails to load through Ash, which breaks reads and — because the
  catalog sync's find-existing-side lookup then errors instead of matching —
  makes re-sync raise a duplicate-side constraint (~1,600 failures in prod).
  This is the same failure `reclassify_pool_ownership_as_aspect` fixed, for the
  symmetric case where the stale value sits in `aspect` rather than `ownership`.

  Rewrite those rows to the classification the current MarvelCDB sync writes:
  the pool moves to `ownership`, `aspect` becomes NULL.

  Hand-written data migration (a deliberate exception to the
  "migrations are managed by ash.codegen" rule).
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE card_sides
    SET ownership = 'encounter', aspect = NULL, updated_at = now()
    WHERE aspect = 'encounter'
    """)

    execute("""
    UPDATE card_sides
    SET ownership = 'basic', aspect = NULL, updated_at = now()
    WHERE aspect = 'basic'
    """)
  end

  def down do
    # No-op: the corrected state (pool in `ownership`, `aspect` NULL) is exactly
    # what a clean sync writes. Restoring the old ownership-only value into
    # `aspect` would reintroduce the un-loadable rows this migration removes, so
    # reverting is intentionally not done.
    :ok
  end
end
