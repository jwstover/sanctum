# Card Model v2 — Follow-up

Improvements to the `Sanctum.Games.Card` / `CardSide` model that clean up
awkward parts of MarvelCDB's card representation. **Out of scope for the deck
sync work** — tracked here so it isn't lost. Ordered roughly by value.

## 1. Bug: `resource_*` fields are read under the wrong names

`Sanctum.MarvelCdb.prepare_card_side_attrs/2` reads `resource_energy_count`,
`resource_physical_count`, `resource_mental_count`, `resource_wild_count`. The
MarvelCDB API fields are actually `resource_energy`, `resource_physical`,
`resource_mental`, `resource_wild` (integer values). The `*_count` variants are
always `null`, so **every card's resource icons are currently stored as nil**.

- Confirmed live: `01088` "Energy" → `{"resource_energy": 2, "resource_energy_count": null}`.
- One-line fix, worth doing regardless of the v2 work.

## 2. Stats as structured values (value / star / scaling)

MarvelCDB spreads each stat across up to ~4 parallel columns. A stat really has
three independent axes:

```elixir
# embedded type, one per stat
%{
  value:   integer | nil,                          # the printed number
  star:    boolean,                                # ★ — a card effect relates to this stat
  scaling: :flat | :per_player | :per_group        # unified, one direction
}
```

- **value and star co-occur** — e.g. Klaw has `attack: 2, attack_star: true`
  (2 attack *and* a ★ effect). Star is not an alternative to the value.
- **scaling** mostly applies to health (villains/minions) and scheme threat.
  Derive the enum at sync time from MarvelCDB's inconsistent booleans:
  - health: `health_per_hero` → `:per_player`, `health_per_group` → `:per_group`, else `:flat`
  - threat: `X_per_group` → `:per_group`, `X_fixed` → `:flat`, else `:per_player`
- Community term is **per_player** (not per_hero); `_per_hero` naming stays
  confined to the sync-mapping layer.

Stats to convert: `attack`, `thwart`, `defense`, `recover`, `health`, and the
three scheme threats (`base_threat`, `escalation_threat`, `max_threat`).
Collapses ~40 columns into ~8 structured fields with uniform rendering.

## 3. Split `faction_code`'s two concepts

MarvelCDB's `faction_code` overloads card *ownership* (`hero`, `encounter`) and
*aspect* (`aggression`/`justice`/`leadership`/`protection`). Keep "which pool"
distinct from a nullable `aspect` (player cards only) to remove `case` noise.

## 4. Drop the `real_*` duplication

`name`/`real_name`, `text`/`real_text`, `traits`/`real_traits` — the `real_*`
variants are the unlocalized English source. For an English-only app that's two
fields per value; pick one canonical field.

## 5. Collapse reprints via `duplicate_of_code`

A reprinted card gets a new code with `duplicate_of_code` pointing back. The
sync upserts on `base_code`, so a reprint becomes a *second* `Card`. Unify into
a canonical card + printings so the catalog dedupes as more packs are added.

## Skip / leave as-is

`octgn_id`, `pack_legacy`, `url`, `spoiler`, `hidden`, `position`/`set_position`
(client cruft); `stage` mixed roman/arabic (already handled by
`stage_to_integer`); HTTP 500 on unknown codes (already handled with
`retry: false`).
