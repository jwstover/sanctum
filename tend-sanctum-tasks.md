# Tend task export: project "Sanctum"

Exported from the tend project **Sanctum** (source project id 4, cwd `/Users/jacob.stover/code/personal/sanctum`) on 2026-10-20. 40 tasks, ordered by source id.

## Notes for the importing agent

- `#<id>` is the task id **on the source instance**. Ids will differ on the target; remap them.
- `parent` refers to another task in this file by source id. Recreate the hierarchy: parents are #99 (TTS import) and #113 (custom content sets). Create parents first.
- `state` uses tend's states: `inbox`, `todo`, `doing`, `review`, `blocked`, `done`, `someday`.
- No task here has `depends_on` / `blocks` links, and none has a priority set. Bodies still mention other tasks by `#id` in prose; remap those references if you want them to stay accurate (all of them point at tasks inside this file, except where noted).
- Bodies are reproduced verbatim from the source `body_md`. They contain plan/implementation/review logs from earlier agent runs, including PR links to https://github.com/jwstover/sanctum.
- Task #522 (the task that asked for this export) is included last for completeness; you can skip it.

## Index

| id | parent | state | title |
|---|---|---|---|
| 98 | | done | Improve user workflow for custom content |
| 99 | | doing | Import to tabletop simulator |
| 103 | 99 | done | Bag-name resolution layer: Sanctum card/hero → Hitch bag entry names |
| 104 | 99 | done | Public deck-import JSON API for the tile |
| 105 | 99 | review | TTS importer tile in Lua, written from scratch |
| 106 | 99 | inbox | Tile clones all pieces, with mat placement |
| 107 | 99 | inbox | Coverage re-measure against a freshly updated mod + surface 'card not found' misses |
| 108 | 99 | inbox | Deck page affordance: import id with copy button + install link |
| 109 | 99 | inbox | Ship the tile as a downloadable Saved Object + install docs |
| 110 | 99 | inbox | Message Hitch before announcing |
| 111 | 99 | inbox | Stretch: spawn homebrew cards as Custom_Card objects |
| 112 | 99 | inbox | Blocker before shipping: self-replicating Lua payload in the mod |
| 113 | | doing | Custom content: sets, publishing, and discovery |
| 114 | 113 | done | 1. Add SetKind lookup resource + seed official kinds |
| 115 | 113 | done | 2. Add HomebrewSet resource with policies and domain actions |
| 116 | 113 | review | 3. Point Card/CardAlt/Aspect at sets |
| 117 | 113 | review | 4. Re-point read policies from project to set |
| 118 | 113 | todo | 5. Drop the project FK and trim HomebrewProject |
| 119 | 113 | todo | 6. Set workspace LiveView; project page becomes a set index |
| 120 | 113 | todo | 7. Set metadata editing + open kind combobox |
| 121 | 113 | todo | 8. Set deletion with blast-radius confirmation |
| 122 | 113 | todo | 9. Move cards between sets + parent/child nesting |
| 123 | 113 | todo | 10. Creator-scoped slugs and public routing |
| 124 | 113 | todo | 11. Publish flow: visibility ladder, attestation, username gate |
| 125 | 113 | todo | 12. Unlisted share links |
| 126 | 113 | todo | 13. Public set directory + set detail page |
| 127 | 113 | todo | 14. Report/takedown flow + lift the admin gate |
| 128 | 113 | todo | 15. origin: search field in the card pool |
| 129 | 113 | todo | 16. Alt-art gallery |
| 130 | 113 | todo | 17. UserArtPreference: apply chosen art at render |
| 131 | 113 | todo | 18. SetRelease + review workflow |
| 132 | | doing | Investigate how we can generate "how-to" or demo videos |
| 133 | | todo | Google Drive import for homebrew content |
| 134 | | todo | Friendly referential integrity for cards used in decks |
| 135 | | todo | Custom aspects, phase 2 (creator-defined aspects) |
| 136 | | todo | Bulk vision enrichment: extract-all per set |
| 137 | | someday | Custom content: deferred ecosystem + play integration |
| 454 | | done | Move Jessica Jones and Luke Cage packs to wave 11 |
| 455 | | review | Admin allow editing card image from public card show page |
| 522 | | doing | dump tasks to md for import |

---

## #98 Improve user workflow for custom content

- state: done

I would like to review how custom content is handeld by this application. I would like to lock down the workflows from both the creator and consumer perspective so that we have a solid direction to build off of. 

# How custom content is organized now

Right now most of the community maintains their custom content in google drive or dropbox. Sets or at least related work is grouped in folders, but the overall structure varies by creator. The important takeaway from this is that we need to make it easy for creators to organize and manage their custom content in the way that feels natural to them. I think we may want to have some kind of folder organization structure unless you can think of something better. 

# Discoverability

From the other side of the picture, discoverability is really poor right now. With content scattered across various google drives and in different structures / formats, it's hard to find what you're looking for, or to even know what is available. Whatever approach we come up with needs to solve this problem.

Users should be able to browse the custom content that exists. I would like this to behave something like how the packs are browsealbe now. The difficulty I forsee with this is if we allow arbitrary folder structures, how do we decide what to expose in the browser. 

# Types of custom content

There are two main types of custom content that I think that we need to handel. 

## Alternate Art 

These are new custom "printings" of official cards. They need to be able to be linked to existing cards so that they show up in the alt art section for the official card. 

# Custom Hero / Scenario / Aspect Cards

This can be entirely new custom heroes, scenarios, and aspects. This part requires that the user also be able to enter the details of each card, like the rules text, title, type, etc. And I think that these should probably be organized into sets or packs similar to how the official content is organized. 

# Versioning

The custom content community has a strict review and versioning process which helps to make sure that the custom content for the game maintains a certain level of quality and parity with the game. We'll want to allow for the addition of versioning, comments, reviews etc for the approval process. I don't want to build this now, but it's important to keep this in mind. 

---

## #99 Import to tabletop simulator

- state: doing

The community standard for playing Marvel Champions using Tabletop Simulator is Hitch's mod for marvel champions. It has an importer that allows you to import a decklist from marvelcdb. I would like to allow the same thing from Sanctum.

**Investigation complete** (see log entries). Decision below.

## Approach: a Sanctum importer tile, not an asset export

Sanctum serves **card names only**; a small importer tile running inside the user's own subscribed copy of Hitch's mod resolves those names against the mod's own card bag and clones the real objects onto the table.

Why this shape (rejected alternatives are in the log):

- **Stock Cerebro can't be redirected.** Its three MarvelCDB base URLs are hard-coded constants in a Workshop mod — no host override, no URL parsing.
- **A static Saved Object export would mean hotlinking Hitch's assets.** It would bake `steamusercontent-a.akamaihd.net` URLs from his mod into files Sanctum serves — borrowed Valve bandwidth, no license (Workshop items carry none), and silent breakage when he re-uploads a sheet. Wrong thing to publish to the community.
- **The tile redistributes nothing.** Art comes from the mod copy the user already subscribed to on Steam. Written from scratch (~100 lines) rather than forked from Cerebro's 613, so no Lua of Hitch's ships either — what's left is interoperation, normal practice in TTS.
- **Fidelity comes free.** Cloning the mod's real objects gives the HP counter, nemesis placement, mat positioning and every per-hero special case without reimplementing any of it.

Verified feasible: `ImporterCards` (GUID `7fd666`) and the Cerebro tile are both **top-level objects** in the mod's `ObjectStates` (190 top-level), so `getObjectFromGUID("7fd666")` resolves from any object spawned into that table.

## Scope: all pieces

Identity, player deck, obligation + nemesis set, side decks, HP counter — all of it, matching what Cerebro does today.

## What the tile clones, by bag entry

| Piece | Bag entry (`7fd666`) |
|---|---|
| Hero kit | `"<hero> Cards"` — Deck, 15–16 cards |
| Identity + obligation + nemesis | `"<hero>"` — Deck, 7 objects |
| HP counter | `"<hero>'s HP Counter"` — `Custom_Tile`, self-contained Lua (no `Global` / `getObjectFromGUID` refs) |
| Side decks | `"Storm Weather Deck"`, `"Doctor Strange Invocation Deck"`, `"Iceman Frostbite Deck"`, `"Hercules Gift Deck"`, `"Hercules Labor Deck"` |
| Aspect / basic / pool cards | per-card lookup in `BasicCards` / `JusticeCards` / `ProtectionCards` / `LeadershipCards` / `AggressionCards` / `PoolCards` |

## Matching rules

- Cards: `Nickname == name` and `Description == subname`, restricted to the pool for the card's aspect. Sanctum knows each card's aspect, so this beats Cerebro's `faction_code` guess.
- Normalize subname: nil, `""`, and `subname == name` all mean "no subtitle" (2603/3669 rows are `== name`, mostly identity cards; 241 carry a real subtitle).
- Collisions are benign — only 29 `(pool, name, subname)` triples repeat, all alternate arts or reprints (3× Energy/Strength/Genius, 2× Taunt, …). Pick-first is safe.
- Heroes: `heroes.hero_name` matches the bag names directly for 63/69. Apply Cerebro's suffix rule for the two alts: `27030a` → `" (Miles Morales)"`, `51001a` → `" (Shuri)"`.

## Known gaps (mod snapshot dated 2 May 2026 — re-measure against a fresh subscription)

- 44 / 784 player-deck-eligible cards absent from the mod entirely (5.6%): Anole, Blindspot, Bling!, Echo, Ghost Rider, Indra, the `Innate *` cycle, …
- 4 heroes absent: Daredevil, Echo, Jessica Jones, Luke Cage.
- Gaps surface as a loud "Card not found" broadcast, same as Cerebro today. Indexing the whole mod rather than just the importer bag would raise coverage 89.7% → 94.4%, but that only matters for the rejected export path.

## Before announcing

- Message Hitch (Discord contact on the Workshop page) as courtesy — and because the better end state is a Sanctum source option *inside* Cerebro, which already has the UI, the bag and the special cases.
- Layer-1 caveat stands for the whole ecosystem: the card art is Marvel / FFG-Asmodee IP and nobody in this chain holds rights. Stay non-commercial.
- Going public changes the traffic profile against MarvelCDB's API, and publicly redistributing scans mirrored from MarvelCDB is its own exposure — separate from Hitch, worth its own look.

## Follow-ups, not in scope here

- Sanctum's own card images (300×419 for older cards) are too soft to be the art source. Fixing that is the only fully self-owned path and the precondition for a standalone Saved Object export that works without Hitch's mod. Separate task.

## Bearer-token decision (from #104)

Nothing in Sanctum mints an API bearer token today — `AuthController.success/4` drops `_token`, there's no `api_key` auth strategy, and every sign-in route is browser/session-only. Shipped the owner-via-bearer path anyway in #104 (the `:api` pipeline's `load_from_bearer` + `set_actor` cost nothing and never halt, and the path is testable via `AshAuthentication.Jwt.token_for_user/1`), but in practice v1 is published-only until a token-minting story exists. That's acceptable per the parent task's own acceptance criteria.

Note for #105: `plug :accepts, ["json"]` on `/api/decks/:id/tts` returns **406** if the tile's `WebRequest` sends an `Accept` header that is neither `application/json` nor `*/*` — worth checking on the first live fetch against the tile.

Note from #105 planning (2026-09-30): the locally installed Hitch's mod is now v14.2.2 (saved 2026-09-01). Its `ImporterCards` bag (`7fd666`, a plain `Bag` with 214 entries) now includes `Daredevil`, `Echo` and `Daredevil Sense Deck`. That means the "4 heroes absent" figure is stale, and so is #103's `daredevil_sense_deck → nil`. Re-measure both in #107.

---

## #103 Bag-name resolution layer: Sanctum card/hero → Hitch bag entry names (subname normalization, aspect→pool, Miles/Shuri suffix rule)

- state: done
- parent: #99

Parent: task #99 "Import to tabletop simulator" — read its body first for the full decision record (why a tile, not an asset export).

## Context

We are building a Tabletop Simulator importer for Sanctum decks. The shape: Sanctum serves **card names only** over a JSON API; a small Lua tile running inside the user's own subscribed copy of **Hitch's Marvel Champions mod** looks those names up in the mod's own object bags and clones the real objects onto the table. Nothing of Hitch's is redistributed.

That means the server has to hand the tile strings that match **the mod's bag entry names**, not Sanctum's internal ids. This subtask is that translation layer — pure Elixir, no HTTP, no Lua.

The mod exposes an `ImporterCards` bag (GUID `7fd666`) whose entries are named after heroes, plus per-aspect card bags. Entry shapes we must produce names for:

| Piece | Bag entry name |
|---|---|
| Hero kit (15–16 signature cards) | `"<hero> Cards"` |
| Identity + obligation + nemesis set (7 objects) | `"<hero>"` |
| HP counter | `"<hero>'s HP Counter"` |
| Side decks | literal names: `"Storm Weather Deck"`, `"Doctor Strange Invocation Deck"`, `"Iceman Frostbite Deck"`, `"Hercules Gift Deck"`, `"Hercules Labor Deck"` |
| Individual player cards | matched inside a pool bag: `BasicCards`, `JusticeCards`, `ProtectionCards`, `LeadershipCards`, `AggressionCards`, `PoolCards` |

## Deliverable

A new module (suggest `Sanctum.TTS.BagNames` in `lib/sanctum/tts/bag_names.ex`) plus tests. Functions along the lines of:

- `hero_bag_names(hero)` → `%{identity: "...", kit: "... Cards", hp_counter: "...'s HP Counter"}`
- `card_lookup(card)` → `%{pool: "JusticeCards", name: "...", subname: nil | "..."}`
- `side_deck_bag_name(side_deck)` → the literal mod name, or `nil` if unmapped

Keep it a pure function of already-loaded structs — the API layer (task #104) does the loading. No Ash reads inside if avoidable; if a lookup table is needed, make it a module attribute.

## Rules (established during investigation — do not re-derive)

**Card matching.** In the mod, a card object is matched by `Nickname == name` and `Description == subname`, restricted to the bag for that card's aspect. Sanctum stores aspect on the `CardSide` (`Sanctum.Games.Card` → `card_sides` / `primary_side`; see `CLAUDE.md` § Card Data Model), plus a separate `CardOwnership` enum (`:player | :basic | :pool | :hero | :encounter | :campaign`). Mapping:

- aspect `justice/protection/leadership/aggression` → `JusticeCards` / `ProtectionCards` / `LeadershipCards` / `AggressionCards`
- ownership `:basic` → `BasicCards`
- ownership `:pool` → `PoolCards`
- `:hero` ownership cards come from the hero kit deck, not a per-card lookup — they should not produce a card lookup at all

Because Sanctum knows the real aspect, this beats Cerebro's `faction_code` guess.

**Subname normalization.** `nil`, `""`, and `subname == name` all mean "no subtitle" — emit `nil` (or `""`, whichever the tile side agrees on; document the choice). Measured on the current catalog: 2603 / 3669 sides have `subname == name` (mostly identity cards); only 241 carry a real subtitle.

**Collisions are benign.** Only 29 `(pool, name, subname)` triples repeat, all alternate arts or reprints (3× Energy / Strength / Genius, 2× Taunt, …). Pick-first is safe; don't build disambiguation.

**Hero names.** `Sanctum.Heroes.Hero.hero_name` matches the mod bag names directly for 63 / 69 heroes. Two alts need Cerebro's suffix rule, keyed on the hero's `base_code`:

- `27030a` → append `" (Miles Morales)"`
- `51001a` → append `" (Shuri)"`

(4 heroes — Daredevil, Echo, Jessica Jones, Luke Cage — are absent from the mod entirely; that's a coverage gap handled in task #107, not a naming problem. This layer should still produce their names.)

**Side decks.** Sanctum derives built-in side decks from catalog sets named `<hero_set>_<label>_deck` — see `Sanctum.Decks.SideDecks.builtin_for_hero/1` and the `Sanctum.Decks.SideDeck` struct (`key` is the set slug, `name` is e.g. `"Invocation Deck"`). The mod's names are hero-prefixed (`"Doctor Strange Invocation Deck"`), so the mapping is roughly `"<hero_name> <SideDeck.name>"` — verify against the five literal names above rather than trusting the pattern, and return `nil` for anything unmapped so the tile can report a miss.

## Acceptance

- Unit tests covering: the two suffix heroes, a hero with no suffix, all three subname-normalization cases, one card per pool (incl. `:basic` and `:pool`), all five side decks, and a `:hero`-ownership card producing no card lookup.
- A test (or a mix task / test-tagged script) that walks the whole live catalog and asserts every player-deck-eligible card produces a `(pool, name, subname)` triple without crashing — the coverage numbers themselves are task #107's job.
- `mix ck` clean.

## Depends on / blocks

Nothing blocks this — it's the first buildable piece. Blocks #104 (the API serializes what this returns) and informs #105/#106 (the tile's matching logic must agree with the normalization choice made here).

## Log — 2026-09-12 (Implement)

**Done.** Branch `tts-bag-names`, stacked on `deck-side-decks` (it pattern-matches `%Sanctum.Decks.SideDeck{}`). One commit: `feat(tts): bag-name resolution layer for Hitch's TTS mod`. Not pushed.

Files:
- `lib/sanctum/tts/bag_names.ex` — `Sanctum.TTS.BagNames`: `hero_name/1`, `hero_bag_names/1`, `card_lookup/1`, `side_deck_bag_name/1`, `normalize_subname/2`. Pure; lookup tables are module attributes; no Ash reads.
- `test/sanctum/tts/bag_names_test.exs` — 21 tests + 2 doctests covering every acceptance case (suffix heroes, unsuffixed hero, three subname cases, one card per pool incl. basic + 'Pool, all five side decks, `:hero` card → nil, unloaded `primary_side` raises).
- `lib/mix/tasks/sanctum.tts_bag_names.ex` — `mix sanctum.tts_bag_names` walks the live catalog (official cards whose primary side is `:player`/`:basic`), fails non-zero if any yields no triple, and prints per-pool counts plus every hero's bag name and side-deck mapping. Against the current dev catalog: 815/815 resolve (Aggression 126, Basic 239, Justice 134, Leadership 147, Pool 34, Protection 135; 191 with a real subtitle).

`mix ck` clean.

**Decisions / deviations from the task text (verified against the catalog):**
- **Subname contract: `nil`.** `nil`, `""`, and `subname == name` all emit `nil` (JSON `null`). The tile (#105/#106) must treat a `null` subname as "Description is empty".
- **`pool` is an aspect, not an ownership.** `CardOwnership` has no `:pool`; Deadpool's cards are `ownership: :player, aspect: "pool"`. Mapped `aspect "pool"` → `PoolCards`.
- **Hero suffix keyed on bare `base_code`.** Sanctum stores `"27030"` / `"51001"` (no side letter); the resolver strips a trailing side letter so `"27030a"` also works.
- **Side decks map by explicit table**, not the `"<hero> <SideDeck.name>"` pattern. Extra key `"iceman_frostbite"` → `"Iceman Frostbite Deck"` because Iceman's Frostbite cards ship in the catalog as set `iceman_frostbite` (no `_deck` suffix), so `SideDecks.builtin_for_hero/1` doesn't currently surface it — worth a look in #107. `daredevil_sense_deck` → `nil` (the mod has no Sense deck).
- `card_lookup/1` also returns `nil` for `:encounter`/`:campaign`, for a `:player` card with an unmapped (custom) aspect, and for a card with `primary_side: nil`; it raises if `primary_side` is `%Ash.NotLoaded{}`.
- Local catalog shows 0 duplicate `(pool, name, subname)` triples (the 29 measured earlier were pre-dedup); pick-first stands.

**For #104:** load `:primary_side` on cards and pass `Hero` + `SideDeck` structs straight in.

## Review — 2026-09-12 (Review step, iteration 1)

**Passed.** No changes requested. Reviewed commit `cf0457e1` on branch `tts-bag-names` (stacked on `deck-side-decks`, not pushed); it touches exactly the three files listed in the Implement log.

Verified:
- `mix test test/sanctum/tts/bag_names_test.exs` — 2 doctests, 21 tests, 0 failures. Every acceptance case is covered (Miles/Shuri suffix, unsuffixed hero, all three subname cases, one card per pool incl. `:basic` and `pool`, all five side decks, `:hero` card → `nil`).
- `mix ck` clean; `mix compile --force --warnings-as-errors` clean.
- `mix sanctum.tts_bag_names` against the dev catalog: 815/815 eligible cards resolve (Aggression 126, Basic 239, Justice 134, Leadership 147, Pool 34, Protection 135; 191 with a real subtitle; 0 duplicate triples). All 69 heroes name correctly, including both suffixed alternates alongside their unsuffixed originals, and the four heroes absent from the mod still produce names.
- Catalog claims spot-checked: `iceman_frostbite` exists (1 card, `:hero` ownership, no `_deck` suffix) and `SideDecks.builtin_for_hero/1` returns `[]` for Iceman, so the extra table key and the #107 flag are both correct. `daredevil_sense_deck` → `nil` confirmed. No hero has a `nil` `hero_name`, so the `is_binary` guard on `hero_name/1` is safe.
- Logic: clause ordering in `card_lookup/1` is sound (`NotLoaded` raise → `nil` → recurse into loaded side → `CardSide`); a bare `CardSide` skips the `Card` clauses because it has no `:primary_side` key. `pool/2` correctly yields `nil` for `:player` with `nil`/custom aspect. Module is pure with module-attribute tables and no Ash reads, as specified. Mix task follows the sibling-task conventions (`@requirements ["app.start"]`, `Mix.raise` on failure).

Observation for #107 (not a defect here): the `iceman_frostbite` set holds only one card in the local catalog, which looks like a sync/catalog gap rather than a naming issue.

## Complete — 2026-09-12

**PR opened:** https://github.com/jwstover/sanctum/pull/363 (`tts-bag-names` → `deck-side-decks`, stacked). The base branch got its own PR at the same time so the stack resolves: https://github.com/jwstover/sanctum/pull/362 (`deck-side-decks` → `main`). #363 should merge after #362.

---

## #104 Public deck-import JSON API for the tile: names only, published-or-owner policy, rate limited (first /api scope in the router)

- state: done
- parent: #99

Parent: task #99 "Import to tabletop simulator" — read its body first for the full decision record.

## Context

The TTS importer tile (task #105) runs Lua inside the user's copy of Hitch's Marvel Champions mod and fetches a deck from Sanctum over `WebRequest`. This subtask is the endpoint it calls.

The payload is **card names only** — no image URLs, no asset references, nothing sourced from Hitch's mod. The tile resolves names against the mod's own bags. That constraint is the whole legal/ethical basis of the approach; do not add image or asset fields "for convenience".

This will be **Sanctum's first public JSON API**. `lib/sanctum_web/router.ex` already has an `:api` pipeline (`:accepts json`, `load_from_bearer`, `set_actor`) and a commented-out `scope "/api"` placeholder near the bottom — this is what fills it in. There are currently no JSON controllers except `DeployNoticeController` (bearer-token webhook) and `ErrorJSON`.

## Deliverable

`GET /api/decks/:id/tts` (name it whatever reads best — `.../tts` signals the payload is shaped for the importer, leaving room for a generic deck API later).

- Controller under `lib/sanctum_web/controllers/` + a JSON view module, following the existing controller conventions.
- `:id` is the deck's UUID primary key (`Sanctum.Decks.Deck` uses `uuid_v7_primary_key`). Accept the bare UUID; consider also accepting the short form the deck page surfaces in task #108 if that turns out to be different.
- Serialize using the bag-name layer from task #103 — the controller loads, that module translates.

Suggested response shape (settle it with #105/#106; whatever you pick, version it):

```json
{
  "version": 1,
  "deck": { "id": "...", "title": "...", "aspects": ["justice"] },
  "hero": { "identity": "Spider-Man", "kit": "Spider-Man Cards",
            "hp_counter": "Spider-Man's HP Counter" },
  "side_decks": ["Doctor Strange Invocation Deck"],
  "cards": [ { "pool": "JusticeCards", "name": "Skilled Investigator",
               "subname": null, "quantity": 2 } ]
}
```

Include the hero kit / identity / HP counter / side decks as their own fields rather than folding them into `cards` — the tile clones those as whole bag objects, not per-card lookups (#106).

## Policy

Reuse the resource policy already on `Sanctum.Decks.Deck` rather than reimplementing access rules:

```elixir
policy action_type(:read) do
  authorize_if expr(visibility == :published)
  authorize_if expr(owner_id == ^actor(:id))
end
```

So: read the deck **with authorization on**, actor from the `:api` pipeline's `set_actor`. A `:published` deck is public; a `:private` deck resolves only for its owner via bearer token. A miss must return 404, not 403 — don't leak the existence of private decks.

Open question to resolve while building: is there actually a way for a user to obtain a bearer token today? If not, decide whether private-deck import is in scope for v1 or whether published-only is acceptable to ship (published-only is fine — the tile is aimed at sharing decklists). State the decision in a log entry on #99.

## Rate limiting

Use the existing `Sanctum.RateLimit` (Hammer, ETS backend, already supervised in `lib/sanctum/application.ex`) following the pattern in `lib/sanctum/accounts/auth_limits.ex`. Note its moduledoc caveat: counters are **per-node**, so with multiple Fly machines the effective limit is `limit × machines` — size the ceiling with that slack in mind.

Key on remote IP. Sizing: a real import is one request per deck, so something like 30/minute per IP is generous for humans and still caps scraping. Return `429` with a plain JSON body on trip.

Also worth a thought (and a note on #99): this endpoint is a public read path over the whole deck catalog. It doesn't hit MarvelCDB, so it doesn't change our upstream traffic profile — but it does make the catalog trivially enumerable. Since deck pages are already public HTML, that's not a new exposure; confirm rather than assume.

## Acceptance

- Controller tests: published deck → 200 with the expected shape; private deck anonymous → 404; private deck as owner → 200; unknown UUID → 404; malformed id → 404 (not a 500); rate limit trip → 429.
- No image URLs or Hitch-sourced strings anywhere in the payload beyond the bag names from #103.
- CSP / router: confirm the `/api` scope doesn't accidentally pick up the `:browser` pipeline's CSP or CSRF plugs.
- `mix ck` clean.

## Depends on / blocks

Depends on #103 (bag names). Blocks #105 (the tile has nothing to fetch until this exists) and #108 (the deck-page affordance surfaces whatever id this endpoint accepts).

## Plan

**Goal.** Add Sanctum's first public JSON endpoint, `GET /api/decks/:id/tts`, returning a versioned names-only payload the TTS importer tile (#105/#106) resolves against Hitch's mod bags. Fills the commented-out `/api` scope, rate-limits the `:api` pipeline, reuses `Deck`'s existing published-or-owner read policy.

**Done when.**
- `GET /api/decks/<published uuid>/tts` → 200 with the shape below; no image URLs or mod-sourced strings beyond `Sanctum.TTS.BagNames` output.
- Private deck anonymous → 404; private deck with owner's bearer token → 200; unknown UUID → 404; malformed id → 404 (not 500).
- 31st request inside a minute from one IP → 429.
- The 200 response carries no `content-security-policy` header (proves `/api` didn't pick up `:browser`).
- `mix ck` clean; new tests pass; the one pre-existing failure stays the only failure.

**Files.**
- `lib/sanctum_web/router.ex` — in the `:api` pipeline (lines 22-26) insert `plug SanctumWeb.Plugs.ApiRateLimit` **between `plug :accepts, ["json"]` (23) and `plug :load_from_bearer` (24)**; at lines 200-203 replace the commented placeholder with a live `scope "/api", SanctumWeb.Api do pipe_through :api; get "/decks/:id/tts", DeckTTSController, :show end`.
- `lib/sanctum_web/plugs/api_rate_limit.ex` (new) — `SanctumWeb.Plugs.ApiRateLimit`, shaped like its sibling `plugs/content_security_policy.ex`.
- `lib/sanctum_web/controllers/api/deck_tts_controller.ex` (new) — `SanctumWeb.Api.DeckTTSController`, `use SanctumWeb, :controller`; loads only.
- `lib/sanctum_web/controllers/api/deck_tts_json.ex` (new) — `SanctumWeb.Api.DeckTTSJSON`, a plain module with `def show(assigns)` and no `use` (like `controllers/error_json.ex`); calls `Sanctum.TTS.BagNames`.
- `test/sanctum_web/controllers/api/deck_tts_controller_test.exs` (new).

**Steps.**
1. Plug: `@scale :timer.minutes(1)`, `@limit 30`. `Sanctum.RateLimit.hit({:api, client_ip(conn)}, @scale, @limit)`; `{:allow, _}` → conn; `{:deny, _}` → `put_status(:too_many_requests) |> put_view(json: SanctumWeb.ErrorJSON) |> render(:"429") |> halt()`. Needs `import Plug.Conn` **and** `import Phoenix.Controller, only: [put_view: 2, render: 2]` (`ContentSecurityPolicy` only imports the former). **Position matters both ways**: after `:accepts` because `render/2` needs the `phoenix_format` that `:accepts` sets, and before `:load_from_bearer` so a denied request skips JWT verification and its `tokens`-table lookup. `client_ip/1` = first `fly-client-ip` request header, else `conn.remote_ip |> :inet.ntoa() |> to_string()`. Fly's proxy sets/overwrites `Fly-Client-IP`, so it is not client-spoofable (verified against Fly's request-headers docs). Do **not** read `x-forwarded-for` — spoofable, and Fly doesn't guarantee its position.
2. Controller `show/2`: `actor = Ash.PlugHelpers.get_actor(conn)`, then `Sanctum.Decks.get_deck(id, actor: actor, load: [:hero, deck_cards: [card: [:primary_side]]])`. `{:ok, deck}` → `render(conn, :show, deck: deck, side_decks: Sanctum.Decks.SideDecks.for_deck(deck))`. `{:error, %Ash.Error.Invalid{}}` and `{:error, %Ash.Error.Forbidden{}}` → 404 via `ErrorJSON` `:"404"`. **No catch-all** — let anything else raise so a DB outage can't masquerade as "not found". (Verified: malformed id → `Ash.Error.Invalid/InvalidArgument`, unknown id and policy-filtered private deck → `Ash.Error.Invalid/NotFound`.)
3. JSON view builds the payload via `BagNames.hero_bag_names/1`, `BagNames.card_lookup/1`, `BagNames.side_deck_bag_name/1`.
4. Tests (below).
5. Append the bearer-token decision to task #99's body with `append_task_body(task_id: 99, ...)` — tend reserves log entries for the user, so the task's "log entry" means a body append. Add one line there for #105: `plug :accepts, ["json"]` returns **406** if the tile's `WebRequest` sends an `Accept` header that is neither `application/json` nor `*/*` — worth checking on the first live fetch.

**Payload (version 1).** `version` (1), `deck` `{id,title,aspects}`, `hero` `{identity,kit,hp_counter}`, `side_decks` (array of bag-name strings), `cards` (array of `{pool,name,subname,quantity}` sorted by `{pool,name}` for stable output), `unmapped` (array of strings).
- Deck card whose `card.primary_side.ownership == :hero` → dropped silently; it arrives via the hero `kit` bag.
- Any other deck card where `card_lookup/1` returns `nil` → label it in `unmapped` with `card.primary_side.name`, falling back to `card.code` when `primary_side` is `nil` (a case `card_lookup/1` returns `nil` for, so don't reach into it blindly).
- Side deck where `side_deck_bag_name/1` returns `nil` → dropped from `side_decks`, its `SideDeck.name` goes in `unmapped`.
- `subname` is `null` per #103's contract; `quantity` from `deck_card.quantity`.

**Out of scope.** No image or asset fields, ever. No CORS (TTS `WebRequest` is not a browser). No API-key strategy or token-minting UI. No `remote_ip` dependency and no `endpoint.ex` change. No generic deck JSON API, no AshJsonApi. Don't refactor `deck_live/show.ex`'s loader. Don't add Sentry/telemetry for API rate-limit trips — `AuthLimits.tripped/2` + `maybe_capture/2` are `ex_dna` bait; do not copy them.

**Decisions.**
- Id is the bare UUID only. `Deck` has no slug/short-code attribute, and #108 confirms it surfaces the same id `/decks/:id` already uses.
- **Bearer tokens: nothing in Sanctum mints one today.** `AuthController.success/4` drops `_token`, there is no `api_key` strategy, and every sign-in route is browser/session-only. Ship the owner path anyway — `:api`'s `load_from_bearer` + `set_actor` cost nothing, never halt, and the path is testable via `AshAuthentication.Jwt.token_for_user/1`. In practice v1 is published-only, which the task says is fine. Record on #99.
- Rate limit lives in the `:api` **pipeline**, not the controller, so future `/api` routes inherit it; key `{:api, ip}`, checked before the deck load so 404s count too.
- Enumerability is confirmed not-new exposure: `deck_live/show_test.exs` has an anonymous visitor rendering `/decks/:id`, so deck pages are already public HTML.
- Namespaced `SanctumWeb.Api.*` under `controllers/api/`: there is no prior JSON controller convention to follow (only `ErrorJSON`), and the namespace leaves room for a generic deck API later. `render(conn, :show, …)` resolves `SanctumWeb.Api.DeckTTSController` → `SanctumWeb.Api.DeckTTSJSON`.
- 404-not-403 falls out for free: `Deck`'s read policy is a filter check, so a private deck is simply absent for a non-owner.

**Verify.** DB first: `docker compose up -d postgres` (I started this container while planning; tests need it). build/lint `mix ck`, test `mix test`. **Baseline is red by exactly one**: `test/sanctum_web/live/homebrew_live/show_test.exs:72` ("Alt art") fails pre-existing, from the applied `homebrew-alt-art-wizard` lane — unrelated, leave it. Tests to add, all in `test/sanctum_web/controllers/api/deck_tts_controller_test.exs` (`async: true`): published → 200 + shape; private + anonymous → 404; private + owner bearer → 200; unknown UUID → 404; `"not-a-uuid"` → 404; no CSP header on the 200; 31 requests → 429. Give each test its own `put_req_header("fly-client-ip", "203.0.113.N")` so the node-global ETS counters don't leak across async tests — **and in the 429 loop build a fresh `build_conn()` with that header every iteration** (or `recycle(conn, ~w(fly-client-ip))`), because `Phoenix.ConnTest` recycling keeps only `accept`/`accept-language`/`authorization` and would silently send requests 2..31 to the shared `127.0.0.1` bucket. Copy the hero/deck/card fixture from `test/sanctum_web/live/deck_live/show_test.exs:11-77` — `ex_dna` scans `lib/` only (240 files), so duplication in `test/` is safe. Note `ConnCase.log_in_user/2` is session-only and will **not** authenticate through `:api`; set the `authorization: Bearer <jwt>` header yourself.

**Ship.** GitButler workspace: yes. Merge target: `main`. Base it on: `main` — #103's `tts-bag-names` and its base `deck-side-decks` both show "(merged upstream)" in `but status`, so nothing to stack on. Branch: `tts-deck-api`. Forge: github (CLI: gh). PR title: `feat(api): public deck-import JSON endpoint for the TTS tile`

⚠️ `lib/sanctum_web/router.ex` is **already dirty** in the uncommitted `zz` lane (9 added lines wiring the dev-only `/dev/sign-in/:email` DemoAuthController route, plus unrelated `demos/`, `AUTH_ROADMAP.md`, `CUSTOM_CONTENT_ROADMAP.md` changes). Stage **only** your `:api` pipeline and `/api` scope hunks (`but status -fv` for hunk ids), review the staged diff, then commit — per `CLAUDE.md`.

## PR

https://github.com/jwstover/sanctum/pull/368

## Implementation

Built exactly per plan: `SanctumWeb.Plugs.ApiRateLimit` (30 req/min per `fly-client-ip`) in the `:api` pipeline, `GET /api/decks/:id/tts` filling the router's `/api` scope, `SanctumWeb.Api.DeckTTSController` + `DeckTTSJSON` under `lib/sanctum_web/controllers/api/`, and full test coverage in `test/sanctum_web/controllers/api/deck_tts_controller_test.exs`.

No deviations from the plan's shape, files, or decisions. One correction on contact: `but pr new` doesn't accept `-F`/`-m` with `-t`/`--default` together — dropped `-t` and put the PR title as the file's first line instead.

Left for later, as the plan specifies: bearer-token minting UI/API-key strategy (v1 ships published-only in practice; decision logged on #99), and #105/#108 which consume this endpoint.

3 commits: rate-limit plug, controller+view+route, tests. PR: https://github.com/jwstover/sanctum/pull/368 — all checks green.

---

## #105 TTS importer tile in Lua, written from scratch: deck-id input + WebRequest + clone from bag 7fd666

- state: review
- parent: #99

Parent: task #99 "Import to tabletop simulator" — read its body first for the full decision record.

## Context

This is the client half of the importer: a small object placed on the table inside **Hitch's Marvel Champions mod** in Tabletop Simulator. The user types (or pastes) a Sanctum deck id, the tile fetches the deck from Sanctum's JSON API (task #104), and clones the matching objects out of the mod's own bags onto the table.

Two hard constraints, both load-bearing for why this approach was chosen at all:

1. **Write it from scratch.** Do not fork, copy, or adapt Cerebro's Lua (613 lines). Ours should be ~100 lines of straightforward code. No Lua of Hitch's ships in what we distribute — what's left is pure interoperation, which is normal practice in TTS.
2. **Redistribute nothing.** Art and objects come from the mod copy the user already subscribed to on Steam. The tile never embeds a `steamusercontent-a.akamaihd.net` URL, a card image, or any asset from the mod.

Why a tile and not a Saved Object export of the deck: stock Cerebro's three MarvelCDB base URLs are hard-coded constants in a Workshop mod (no host override, no URL parsing), so it can't be pointed at Sanctum; and a static export would mean hotlinking Hitch's assets. See #99.

## Verified feasible

`ImporterCards` (GUID `7fd666`) and the Cerebro tile are both **top-level objects** in the mod's `ObjectStates` (190 top-level objects total), so `getObjectFromGUID("7fd666")` resolves from any object spawned into that table — including our tile, however the user places it.

## Scope of *this* subtask

Get the skeleton working end to end with **one** piece cloning correctly (the identity deck is the natural first target). The full set of pieces and their placement is task #106.

Deliverable:

- The Lua script, kept in this repo (suggest `priv/tts/` or `assets/tts/` — pick one and note it) so it is version-controlled and reviewable, not only living inside a `.json` Saved Object blob.
- A deck-id input: TTS UI input field or a `Custom_Tile` with an input, plus a visible "Import" button.
- `WebRequest.get(url, callback)` against the #104 endpoint; parse with `JSON.decode` (or the mod's available JSON helper — check what the TTS Lua environment provides in this version).
- `getObjectFromGUID("7fd666")` → `getObjects()` → find the entry whose name matches, `takeObject{...}` to clone it onto the table.
- Error surfacing via `broadcastToAll` — HTTP failure, non-200, malformed JSON, unknown deck id, bag GUID not found (i.e. "you're not in Hitch's mod"). Each should say what to do, not just fail silently.

## Things to get right

- **Clone, don't take.** The bag entries are the mod's masters. Confirm whether `takeObject` on this bag removes the entry (an infinite bag vs. a normal bag behave differently) and make sure a second import still works. If the bag isn't infinite, clone via `spawnObjectData`/`spawnObjectJSON` from the entry's data instead of removing it.
- **Async everywhere.** `WebRequest` and `takeObject` are both asynchronous. Sequence spawns with callbacks or `Wait.condition`, not with a busy loop — spawning many objects in the same frame is a known source of TTS physics chaos.
- **Match the normalization contract from #103.** Whatever "no subtitle" is on the wire (`null` vs `""`), the tile's `Description` comparison must agree. Match on `Nickname == name and Description == subname`, restricted to the pool bag the payload names.
- **Never trigger a modal dialog.** Use `broadcastToAll` / `print`, not anything blocking.

## Acceptance

- In a live TTS session with a fresh subscription to Hitch's mod: paste a real Sanctum deck id, press Import, and the correct identity card appears on the table.
- Importing twice in a row works (nothing consumed from the bag).
- Running the tile in a table that is *not* Hitch's mod produces a clear "this tile must be used inside <mod name>" broadcast, not a Lua error.
- A bad deck id produces a clear broadcast.
- The Lua file is committed and its provenance is documented as written-from-scratch in a comment header.

## Depends on / blocks

Depends on #104 (something to fetch). Blocks #106 (full piece set + placement), #107 (coverage measurement needs a working import), #109 (packaging), #112 (the payload-scan blocker must be cleared before this is *shipped*, but not before it's built).

## Plan

**Goal.** Add a from-scratch Lua importer script, version-controlled at `priv/tts/sanctum_importer.lua`. A user pastes it into any object inside Hitch's mod. The object then gets a deck-id input and an Import button, fetches `GET /api/decks/:id/tts` (built in #104), and clones the deck's identity entry out of `ImporterCards` (`7fd666`) without using up the bag. Only the identity entry is cloned here; #106 adds the remaining pieces.

**Done when.**
- `priv/tts/sanctum_importer.lua` exists (~100–130 lines). Its header comment says: written from scratch for Sanctum, contains no Cerebro or Hitch Lua, embeds no assets, needs *Marvel Champions: Hitch's Table* (Workshop 2514286571).
- `grep -c -E 'steamusercontent|akamaihd|http[s]?://[^"]*\.(png|jpg)' priv/tts/sanctum_importer.lua` → 0. The new ExUnit test (below) passes.
- With the dev server running, `curl -s localhost:4150/api/decks/<published id>/tts | jq -r .hero.identity` prints a value that is exactly an entry `.Nickname` in the local mod file. Check with `jq -r '.ObjectStates[]|select(.GUID=="7fd666").ContainedObjects[].Nickname' "$HOME/Library/Tabletop Simulator/Mods/Workshop/2514286571.json"`.
- The PR body has a **manual live-TTS checklist** for the user, since the implementer cannot run TTS. It covers the task's four acceptance bullets: identity appears; importing twice works; a non-Hitch table shows the mod-name broadcast; a bad id shows a clear broadcast.

**Files.**
- `priv/tts/sanctum_importer.lua` (new) — the whole tile.
- `priv/tts/README.md` (new, ≤25 lines). How to attach the script: in Hitch's table, Objects → Components → Blocks → Square (it needs no image URL), right-click → Scripting → paste → Save & Play. Also how to point `BASE_URL` at `http://localhost:4150` for dev. Note that the Saved Object packaging is #109.
- `test/sanctum/tts/importer_lua_test.exs` (new) — reads the file and asserts it exists, has the provenance header, and has no `steamusercontent`/`akamaihd` string. This guards constraint #2 in CI.
- No existing file changes.

**Steps.**
1. **Constants** at the top of the script: `BASE_URL = "https://sanctummc.com"` (prod `PHX_HOST`; add a comment that dev uses `http://localhost:4150`), `BAG_GUID = "7fd666"`, `MOD_NAME = "Marvel Champions: Hitch's Table"`. Add `local deckInput = ""` and `local busy = false`.
2. **UI.** In `onLoad`, call `self.clearInputs()` and `self.clearButtons()`. Then `self.createInput{input_function="onDeckIdInput", function_owner=self, label="Sanctum deck id or URL", …}` and `self.createButton{click_function="onImportClick", function_owner=self, label="Import", …}`. The input callback signature is `(obj, color, value, selected)`: store `value` in `deckInput` and return nothing.
3. **Id extraction.** `string.match(deckInput, "%x+%-%x+%-%x+%-%x+%-%x+")`, so a bare UUID and a pasted `…/decks/<uuid>` URL both work. If nothing matches, broadcast "Paste a Sanctum deck id or deck URL" and stop before any request.
4. **Bag precheck before fetching.** `local bag = getObjectFromGUID(BAG_GUID)`. If it is `nil`, or its `getName() ~= "ImporterCards"`, broadcast "This tile must be used inside <MOD_NAME> (Steam Workshop). Load that table and try again." and stop.
5. **Fetch.** Use `WebRequest.custom(url, "GET", true, nil, {Accept="application/json"}, onResponse)` instead of `.get`. Sending `Accept` explicitly avoids #104's 406 risk from `plug :accepts`. Set `busy = true` before the call and clear it on every exit path. If `busy` is already true, broadcast "Import already in progress".
6. **Response handling** (fields: `is_error`, `error`, `response_code`, `text`), each case its own broadcast:
   - `is_error` → network failure; show the error and suggest checking the connection.
   - 404 → "Deck not found — check the id, and that the deck is published on Sanctum".
   - 429 → "Too many imports — wait a minute".
   - other non-200 → show the code and the URL.
   - `pcall(JSON.decode, text)` fails or doesn't return a table → "Sanctum sent an unreadable response".
   - `version ~= 1` → "This tile is out of date — get the latest from Sanctum".
   - missing `hero.identity` → report it.
   - non-empty `unmapped` → yellow warning listing the names. This is not an error.
7. **Clone, don't take.** `local entries = bag.getData().ContainedObjects`. If that is nil, broadcast an error. Otherwise find the first entry where `entry.Nickname == hero.identity` (exact `==`: both `Spider-Man` and `Spider-Man (Miles Morales)` exist). Then `spawnObjectData{data=entry, position=self.getPosition() + Vector(0, 2, -4), callback_function=…}`. Leave rotation out so the entry keeps its own rotation. If no entry matches, broadcast "<identity> isn't in this version of <MOD_NAME>'s importer bag". On spawn, broadcast "Imported <deck.title>" in green.
8. **Structure for #106 (keep it this small).** Build a `pieces` list (one entry now: the identity name) and a `spawnNext(i)` that spawns `pieces[i]` and calls `spawnNext(i+1)` from `callback_function`. That gives sequential spawns with no busy loop or same-frame burst. Clear `busy` when the chain finishes.
9. Write the README and the ExUnit test. Commit, then open the PR with the manual checklist.

**Out of scope.** Kit deck, HP counter, side decks, per-card pool lookups, and placement are #106. The coverage numbers are #107. The Saved Object `.json`, the Workshop upload, and the tile art are #109. The deck-page "copy id" affordance is #108. Changes to #103's `BagNames` are out too, including `daredevil_sense_deck → nil`: the installed mod (v14.2.2, 2026-09-01) now has `Daredevil`, `Echo` and `Daredevil Sense Deck`, which I've noted on #99 for #107. Also out: a Lua linter or CI step (none is installed — don't add one), a host override UI, persisting the input via `onSave`, and any reading of or reference to Cerebro's script.

**Decisions.**
- **`priv/tts/` over `assets/tts/`.** `assets/` is esbuild/Tailwind input. Nothing in `mix ck`, the formatter or `ex_dna` touches `priv/tts`, and #109 can serve the file from there later.
- **`spawnObjectData` from `bag.getData()`, not `getObjects` → `takeObject`.** `7fd666` is a plain `"Bag"` (not `Infinite_Bag`, empty `LuaScript`, 214 entries), so `takeObject` would remove the master. Also, `getObjects()` returns only summaries (name/guid/index), which can't be spawned.
- **Matching** is on Nickname only for whole bag entries. For #106's per-card matching: #103's wire contract sends no subtitle as JSON `null`. TTS's `JSON` docs don't say how `null` decodes, so treat `subname == nil or subname == ""` as matching `Description == ""`.
- **Bag precheck happens before the HTTP call**, so the wrong-table error is instant and doesn't use up rate limit.
- **Messages** use only `broadcastToAll(msg, color)`, never modal UI. Prefix each with `[Sanctum]`.

**Verify.** Start postgres with `docker compose up -d postgres`. build/lint: `mix ck` (it runs `mix format`, so check it only reformats your own files); test: `mix test`. **Baseline is red by exactly one test**: `test/sanctum_web/live/homebrew_live/show_test.exs:72` ("Upload button opens the type chooser"), which comes from the unrelated `homebrew-alt-art-wizard` lane. Leave it alone. Test to add: `test/sanctum/tts/importer_lua_test.exs` (`async: true`), using `Application.app_dir(:sanctum, "priv/tts/sanctum_importer.lua")` or a path relative to `File.cwd!`. Lua syntax check: if `luac` is on PATH, run `luac -p priv/tts/sanctum_importer.lua`. It isn't installed today, so say so in the PR rather than installing it. Do the curl/jq check from "Done when".

**Ship.** GitButler workspace: yes. Merge target: `main`. Base it on: `main` (the common base is already the #368 merge, so there is nothing to stack on). Branch: `tts-importer-tile`. Forge: github (CLI: gh). PR title: `feat(tts): Sanctum importer tile for Hitch's TTS mod`. A `feat` commit cuts a release; that's expected. All your files are new. The `zz` lane has unrelated dirty files (`router.ex`, `demos/`, roadmaps), so commit only your three files by their `but status -fv` ids with `but commit -b tts-importer-tile`, review the staged diff, and push with `but push tts-importer-tile`. Never use a bare `but push`.

## PR
https://github.com/jwstover/sanctum/pull/411

## Implementation
- Built `priv/tts/sanctum_importer.lua` (tile), `priv/tts/README.md`, `test/sanctum/tts/importer_lua_test.exs`; branch `tts-importer-tile`.
- Followed the plan. Small additions: `unmapped` entries are plain strings in #103's payload, so the warning handles strings and tables; the bag is re-fetched in the response handler for the spawn.
- `luac` not installed, so the Lua was not syntax-checked; the PR carries the manual live-TTS checklist.
- curl check: `hero.identity` = "Maria Hill", an exact bag Nickname.
- Left for later: kit, side decks, per-card pool lookups (#106).

---

## #106 Tile clones all pieces: identity, player deck, hero kit, obligation + nemesis, side decks, HP counter — with mat placement

- state: inbox
- parent: #99

Parent: task #99 "Import to tabletop simulator" — read its body first for the full decision record.

## Context

Task #105 gets the tile fetching a deck and cloning one piece. This subtask takes it to **feature parity with Cerebro**: every piece a player expects after an import, placed where they expect it.

Scope is explicitly *all* pieces — identity, player deck, hero kit, obligation + nemesis set, side decks, HP counter. That was a deliberate scope decision on #99, not an aspiration.

A key reason the clone-from-the-mod approach was chosen: **fidelity comes free**. Cloning the mod's real objects gives the HP counter, nemesis placement, mat positioning and every per-hero special case without reimplementing any of it. Lean on that — resist rebuilding behavior the mod's objects already have.

## What to clone, by bag entry

The `ImporterCards` bag has GUID `7fd666` and is a top-level object in the mod's `ObjectStates`, so it resolves via `getObjectFromGUID("7fd666")` from anywhere on the table.

| Piece | Bag entry in `7fd666` |
|---|---|
| Hero kit | `"<hero> Cards"` — a Deck, 15–16 cards |
| Identity + obligation + nemesis | `"<hero>"` — a Deck, 7 objects |
| HP counter | `"<hero>'s HP Counter"` — a `Custom_Tile` with self-contained Lua (verified: no `Global` or `getObjectFromGUID` references, so it works standalone once cloned) |
| Side decks | `"Storm Weather Deck"`, `"Doctor Strange Invocation Deck"`, `"Iceman Frostbite Deck"`, `"Hercules Gift Deck"`, `"Hercules Labor Deck"` |
| Aspect / basic / pool cards | per-card lookup in `BasicCards` / `JusticeCards` / `ProtectionCards` / `LeadershipCards` / `AggressionCards` / `PoolCards` |

The `"<hero>"` entry bundles identity **plus** obligation **plus** nemesis set as 7 objects — so those three arrive together and probably need splitting/distributing to their proper spots rather than dropping as one stack.

Server-side names for all of the above come from the bag-name layer (#103) via the API payload (#104), including the `27030a` → `" (Miles Morales)"` / `51001a` → `" (Shuri)"` suffix rule.

## Placement

The mod has player mats with defined zones. Work out placement from the mod's own layout rather than hard-coding world coordinates where possible:

- Player deck → the player's deck slot on their mat
- Identity → the identity slot (hero side up, per convention)
- Obligation + nemesis set → wherever the mod expects encounter-side hero cards (Cerebro's behavior is the reference)
- HP counter → beside the identity
- Side decks → alongside the player area

Decide and document how the tile picks *which* player mat (colour of the clicking player is the obvious answer — `Player.color` from the button callback). Multi-player: importing two decks in one session must not stack them in the same place.

Study what Cerebro does for placement as a **behavioral** reference — observe it, don't copy its code (see the from-scratch constraint on #105).

## Things to get right

- **Build the player deck as one Deck object**, not 30 loose cards. Spawn the cards then group them, or clone into a temporary zone and combine. A pile of loose cards on the mat is a bad import.
- **Sequence the spawns.** `takeObject` is async; spawning ~40 objects in one frame throws them around. Chain callbacks or use `Wait.condition`, and consider spawning `smooth = false` / locked-then-unlocked.
- **Per-hero special cases** (heroes with two side decks — Hercules has Gift *and* Labor; heroes with none) must fall out of the payload, not out of `if hero == "..."` branches in the Lua.
- **Missing pieces are not fatal.** A hero absent from the mod, or a card the mod doesn't have, should import everything else and report the misses (see #107) — never abort the whole import.

## Acceptance

Manual verification in a live TTS session against a fresh subscription, for at least:

- A plain hero with a single aspect (e.g. Spider-Man / Justice) — full correct import, deck as one Deck object, HP counter functional (click it, watch the counter change).
- Doctor Strange — Invocation side deck present.
- Hercules — **both** Gift and Labor decks present.
- Miles Morales and Shuri — the suffix rule resolves.
- A two-aspect / pool-card deck — cards resolve out of the right pool bags.
- Two imports in one session onto different player mats.

Screenshots or a short clip of a completed import, attached to the task log, is the useful artifact here.

## Depends on / blocks

Depends on #105 (working tile skeleton) and #104/#103 (payload carries every piece's bag name). Blocks #107 (coverage measurement runs against the complete importer) and #109 (packaging ships the finished tile).

---

## #107 Coverage re-measure against a freshly updated mod + surface 'card not found' misses back to the user

- state: inbox
- parent: #99

Parent: task #99 "Import to tabletop simulator" — read its body first for the full decision record.

## Context

Two jobs, both about **what the mod doesn't have**:

1. Re-measure coverage against a **freshly updated** subscription to Hitch's mod.
2. Make misses legible to the user at import time instead of silently producing a short deck.

## Why re-measure

Every coverage number on #99 came from a mod snapshot dated **2 May 2026**. Hitch updates the mod as new packs release, so the gaps have almost certainly moved. Treat the figures below as the previous reading, not as facts:

- **44 / 784** player-deck-eligible cards absent from the mod entirely (5.6%) — Anole, Blindspot, Bling!, Echo, Ghost Rider, Indra, the `Innate *` cycle, …
- **4 heroes** absent: Daredevil, Echo, Jessica Jones, Luke Cage
- Indexing the whole mod rather than just the `ImporterCards` bag would raise coverage 89.7% → 94.4% — but that only matters for the *rejected* static-export path, so **do not** pursue whole-mod indexing here. The tile reads the importer bag; that's the surface that counts.

Deliverable for the measurement half: a repeatable script or mix task that takes the mod's `ObjectStates` JSON (from a current subscription) and Sanctum's catalog and prints the miss list — heroes missing, cards missing, coverage %. Repeatable matters more than pretty: this needs re-running every time a pack drops. Commit it (`priv/` or a `mix sanctum.*` task) and record the new numbers plus the snapshot date in a log entry on #99.

It should reuse the matching rules from the bag-name layer (#103) rather than reimplementing them — a "miss" must mean "the mod genuinely lacks this card", not "our name normalization is off". Sanity-check a handful of reported misses by hand in TTS before believing the total.

## Surfacing misses to the user

Cerebro today broadcasts a loud "Card not found" and carries on. Match or beat that:

- The import **never aborts** on a miss — everything resolvable still lands on the table (see #106).
- Report per-miss with the card's actual name, e.g. `Sanctum import: "Innate Reflexes" is not in this mod — add it manually.`
- Report an absent **hero** distinctly and up front: that's a much bigger failure than one card, and the user should know the import will be substantially incomplete before they start playing.
- Summarize at the end: `Imported 46 of 49 objects. 3 cards missing (see chat).`
- Use `broadcastToAll` / chat only — never a modal dialog.

Optional, decide while building: is it worth Sanctum flagging *before* the user leaves the site — a "3 cards in this deck aren't in the TTS mod" note next to the import affordance (#108)? That requires the server to know the mod's contents, i.e. shipping the miss list as data and keeping it current. Probably not worth it for v1; note the decision either way.

## Acceptance

- The measurement script runs against a current mod snapshot and prints hero + card miss lists and a coverage %.
- New numbers and the snapshot date logged on #99, replacing the 2 May 2026 reading.
- At least three reported misses spot-checked by hand in TTS.
- A live import of a deck containing a known-missing card: the rest of the deck imports, the miss is named in chat, and the summary line is correct.
- A live import for one of the absent heroes: clear up-front message, no Lua error.

## Depends on / blocks

Depends on #106 (measuring and reporting against the complete importer). Blocks #109/#110 — don't publish install docs or message Hitch quoting stale coverage numbers.

---

## #108 Deck page affordance: surface the deck's import id with a copy button + link to tile install instructions

- state: inbox
- parent: #99

Parent: task #99 "Import to tabletop simulator" — read its body first for the full decision record.

## Context

The Sanctum-side UI half of the TTS importer. The tile (#105/#106) needs a deck id typed or pasted into it, so the deck page has to hand the user that id without them digging in the URL bar — and point them at how to install the tile in the first place (#109).

## Deliverable

On the deck detail page — `SanctumWeb.DeckLive.Show` (`lib/sanctum_web/live/deck_live/show.ex`) — an affordance that:

1. Shows the deck's import id.
2. Copies it to the clipboard on click.
3. Links to the tile install instructions.

The page's `<.header>` already carries an `<:actions>` slot with the favorite button, an owner-only "Edit Deck" button, a conditional "MarvelCDB" external link, and `<.back_button>`. A "Tabletop Simulator" action fits naturally there; a small labeled row in the cover panel is the alternative if the header is getting crowded. Match the pinned dark comic-dossier design — reuse existing components (`.button`, `.panel`, `.icon`) rather than introducing new styling.

The id is the deck's UUID primary key (`Sanctum.Decks.Deck`, `uuid_v7_primary_key`), the same value `/decks/:id` already exposes — whatever #104's endpoint accepts. A raw UUID is unpleasant to retype but fine to paste; if #104 grows a shorter accepted form, prefer surfacing that.

## Implementation notes

- **Clipboard needs a JS hook.** There's no copy-to-clipboard component in `SanctumWeb.CoreComponents` today, and no existing hook for it — `assets/js/hooks/` has no clipboard hook. Add a small colocated hook (the codebase's pattern, see the `confirm_button` note in `CLAUDE.md`) using `navigator.clipboard.writeText`, with visible "Copied!" feedback. Guard for `navigator.clipboard` being unavailable on insecure origins, and make the id selectable text so a fallback is always manual-select.
- **Do not use `data-confirm`** anywhere here — see the standing rule in `CLAUDE.md` (WebKit suppresses `window.confirm` in iOS PWA mode).
- **Visibility.** Only meaningful for decks the visitor can actually import. Given #104 serves `:published` decks publicly and `:private` decks only to their owner, showing the affordance on a private deck to a non-owner is moot — they can't see the page anyway. But if #104 lands as published-only (an open question there), hide or disable the affordance on private decks with a note to publish first, rather than handing out an id that 404s.
- Consider the deck **build** page (`build.ex`) too — a user iterating on a deck is exactly who wants to re-import it. Optional for v1.

## Install-instructions link

Points at whatever #109 produces (a docs page, a README, or a Workshop/Steam item page). Until that exists, wire the link to a placeholder route and note the dependency — don't block this on #109 landing.

## Acceptance

- Verify in a real browser against the dev server at `http://localhost:4150` using the `playwright-cli` skill (per `CLAUDE.md`): the affordance renders on a published deck page, the copy button copies the id, and the feedback appears.
- Renders correctly at mobile width — the deck page is used on phones and the header actions wrap.
- Nothing regressed on the existing header actions (favorite, edit, MarvelCDB, back).
- `mix ck` clean.

## Depends on / blocks

Soft-depends on #104 (the id it surfaces must be the id the endpoint accepts) and #109 (the link target). Nothing blocks on this — it's a convenience, not a functional gate — but it's the only thing that makes the feature discoverable, so it should ship with #109/#110.

---

## #109 Ship the tile as a downloadable Saved Object + install docs for the community

- state: inbox
- parent: #99

Parent: task #99 "Import to tabletop simulator" — read its body first for the full decision record.

## Context

Distribution. The tile from #105/#106 is only useful if a player can get it into their own copy of Hitch's mod. In Tabletop Simulator that means a **Saved Object**: a `.json` file the user drops into `Documents/My Games/Tabletop Simulator/Saves/Saved Objects/`, then spawns from the in-game Objects → Saved Objects menu while sitting at Hitch's table.

⚠️ **#112 is a hard blocker on this task.** There is a self-replicating Lua payload in the mod, and the tile must be authored and exported from a clean install with the published JSON scanned for its markers before anything is distributed. Do not publish a Saved Object that hasn't been through that check — read #112 before you export.

## What ships

1. **The Saved Object `.json`** — the tile, its Lua, and nothing else. Specifically it must contain **no** asset URLs pointing at `steamusercontent-a.akamaihd.net` or any other host serving Hitch's art, and no Lua of Hitch's. The tile's own appearance should use a Sanctum-authored image (hosted on our public Tigris bucket, or a plain built-in TTS shape — a plain shape is the safer, zero-dependency choice for v1).
2. **A download route.** Serving a static file from Sanctum, alongside the install docs, is the simplest path. Steam Workshop is the alternative but publishing a Workshop item makes the artifact a mod of its own, which raises questions the download avoids.
3. **Install docs**, covering:
   - Subscribe to Hitch's Marvel Champions mod on the Steam Workshop (the tile is useless without it — say this first and plainly)
   - Download the `.json`, where to put it, per-OS path
   - Load Hitch's table, spawn the tile from Saved Objects
   - Paste a deck id from any Sanctum deck page (#108), press Import
   - What the coverage gaps mean — a small fraction of cards and a few heroes aren't in the mod at all and will be reported in chat (current numbers come from #107; don't quote the stale 2 May 2026 figures)
   - Troubleshooting: "tile says it can't find the bag" → you're not in Hitch's mod; "nothing happens" → check the deck is published
4. Where the docs live: an in-app page under `/decks` or a `docs/` markdown file linked from the deck-page affordance. #108 wires a link to whatever this produces, so settle the URL early and tell that task.

## Provenance and framing

The docs are the public face of the "we redistribute nothing" position, so state it there explicitly: the tile clones objects from the copy of Hitch's mod the user already subscribed to; Sanctum serves card names only; the tile's Lua was written from scratch.

Also carry the ecosystem caveat from #99: the card art is Marvel / FFG-Asmodee IP and nobody in this chain holds rights. Keep everything non-commercial — no donations, no ads, no store links attached to this.

## Acceptance

- #112 cleared and its scan documented.
- The exported `.json` inspected by hand (not just diffed): confirm no Hitch asset URLs, no foreign Lua, no unexpected nested objects.
- Clean-machine test: a second machine (or a wiped Saved Objects dir) with a fresh subscription follows the written docs start to finish and completes an import. Fix whatever step the docs got wrong.
- The Lua in the shipped `.json` matches the version-controlled source from #105 — note how the two stay in sync (a make/mix step that injects the Lua into the JSON is better than hand-editing both).
- Docs link resolves from the deck page (#108).

## Depends on / blocks

Blocked by **#112** (payload scan). Depends on #106 (finished tile) and #107 (accurate coverage numbers to document). Blocks #110 — message Hitch before this goes public, not after.

---

## #110 Message Hitch before announcing; float a Sanctum source option inside Cerebro itself

- state: inbox
- parent: #99

Parent: task #99 "Import to tabletop simulator" — read its body first for the full decision record.

## Context

A human step, not an engineering one — and it comes **before** any public announcement.

Hitch's Marvel Champions mod is the community standard for playing on Tabletop Simulator, and Cerebro (its built-in MarvelCDB importer) is his. Our tile interoperates with his mod: it clones objects out of the copy the user already subscribed to on Steam. That's normal practice in TTS and redistributes nothing of his — but he should hear about it from us rather than discover it.

## Two asks, in one message

1. **Courtesy heads-up.** Describe what the tile does and, just as importantly, what it deliberately doesn't do: no assets copied, no Lua of his reused (ours is ~100 lines written from scratch, not a Cerebro fork), no hotlinking of `steamusercontent-a.akamaihd.net` URLs. It reads names from Sanctum and clones from his bags in the user's own subscription.

2. **Float the better end state:** a **Sanctum source option inside Cerebro itself**. Cerebro already has the UI, the importer bag, and every per-hero special case. A source dropdown there beats a separate tile for everyone — one importer for users, no parallel implementation to maintain, and it's his call how it's presented. Our tile then becomes either unnecessary or a stopgap; say that we're fine with that outcome.

Worth mentioning as the concrete blocker that pushed us to a tile: stock Cerebro's three MarvelCDB base URLs are **hard-coded constants** in a Workshop mod — no host override, no URL parsing — so there's no way for a user to point it at Sanctum today. A single configurable base URL would be a smaller change than a full source option, if he prefers that.

## Contact

Discord contact is listed on the mod's Steam Workshop page.

## Worth being honest about

- Coverage: some cards and heroes are absent from the mod, so imports are incomplete for them. Current numbers come from #107 — use those, not the stale 2 May 2026 reading on #99.
- The layer-1 caveat applies to the whole ecosystem, his mod and Sanctum alike: the card art is Marvel / FFG-Asmodee IP and nobody in this chain holds rights. Everything here stays non-commercial. No need to lecture him about it — he knows — but don't pretend our side is cleaner than it is.

## Also on this task

Going public changes two things beyond Hitch, and each deserves its own look (log findings on #99):

- The traffic profile against **MarvelCDB's API** — our sync becomes load they didn't ask for at a new scale.
- Publicly redistributing card scans mirrored from MarvelCDB into our Tigris bucket is its own exposure, separate from anything to do with Hitch.

## Acceptance

- Message sent; a summary of it and any reply logged on #99.
- If he objects to any part, **stop and re-decide** rather than shipping over the objection — the whole approach was chosen to be something we'd be comfortable defending publicly.
- If he's interested in the in-Cerebro source option, capture what he'd need from us (endpoint shape, a stable base URL, a spec) as a new task.

## Depends on / blocks

Depends on #107 (accurate numbers to quote). Blocks the public announcement — which means it gates the *announcement* of #109, though #109's build work can proceed in parallel.

---

## #111 Stretch: spawn homebrew cards as Custom_Card objects from Sanctum-hosted image URLs

- state: inbox
- parent: #99

Parent: task #99 "Import to tabletop simulator" — read its body first for the full decision record.

**Stretch. Do not start before #106 works.** This is the one part of the importer that Hitch's mod fundamentally cannot cover, and it's also the part with the weakest foundation today.

## Context

The core importer clones objects out of the mod's bags, which means it can only import cards **the mod has**. Sanctum's homebrew content — custom cards created in `/homebrew` — exists nowhere in the mod by definition. For those, the only option is to spawn `Custom_Card` objects pointing at **Sanctum-hosted image URLs**.

That's a different mechanism from everything else in the importer, and it inverts the "we host no art" property that makes the rest of the approach clean: here Sanctum *is* the image host. That's fine — homebrew art is user-created content we already serve — but keep the two paths clearly separate in the code and in the docs.

## What this involves

- Extend the API payload (#104) with a homebrew branch: cards that carry `face`/`back` image URLs and card dimensions instead of a `(pool, name, subname)` bag lookup.
- Extend the tile (#105/#106) to `spawnObjectData` a `Custom_Card` per homebrew card, with `FaceURL` / `BackURL` set to Sanctum's public bucket URLs, correct `CardID`, and sane `Transform`.
- Group homebrew and mod-sourced cards into the **same** player Deck object — a `Custom_Card` and a card cloned from the mod's sheet must merge. Verify this actually works in TTS; different-sheet cards combining into one deck is the risk to test first, before building anything else.

## Prerequisites and hard constraints

- **Image quality is the real blocker.** Per the follow-up note on #99: Sanctum's own card images are 300×419 for older cards, too soft to be a usable art source in TTS, where cards render large. Homebrew uploads may be better than the mirrored MarvelCDB scans, but check the actual dimensions of real homebrew images before assuming. If they're small, this produces a blurry card and isn't worth shipping.
- **TTS fetches the URL directly.** The images must be publicly reachable, CORS-agnostic, and stable. Our Tigris bucket (`sanctum-cards`, see `lib/sanctum/card_images.ex`) is public and fits; confirm TTS can load from it and that it caches rather than refetching per spawn.
- **Homebrew is currently admin-only.** Per `lib/sanctum_web/router.ex`, `/homebrew*` routes sit in the `:admin_routes` live session "TEMPORARILY admin-only while the feature incubates". So the audience for this is one person today. That's a strong argument for keeping it a stretch: revisit when homebrew opens up.
- Homebrew decks may not have a hero in the mod at all — the identity, kit, obligation/nemesis and HP counter all have to come from somewhere. A fully homebrew hero is a much bigger job than homebrew player cards; scope this task to **player cards in an otherwise-normal hero's deck** and spin the rest out if wanted.

## Relationship to the rejected export path

Note the connection, because it's easy to conflate: fixing Sanctum's image quality is the precondition both for this *and* for the standalone Saved Object export that would work without Hitch's mod entirely (the only fully self-owned path). That image work is its own separate task per #99 — this task should not try to solve it.

## Acceptance (if pursued)

- Spike first: hand-build a `Custom_Card` in TTS from a Sanctum-hosted homebrew image and confirm (a) it looks acceptable at table zoom and (b) it merges into a deck with mod-sourced cards. If either fails, stop and log why — that's a complete and useful outcome for this task.
- Then: a homebrew card in a deck imports alongside mod cards, in one Deck object, at acceptable fidelity.

## Depends on / blocks

Depends on #106. Blocks nothing. Do not let this delay #109/#110.

---

## #112 Blocker before shipping: self-replicating Lua payload in the mod — author/export the tile from a clean install, scan published JSON for the markers

- state: inbox
- parent: #99

Parent: task #99 "Import to tabletop simulator" — read its body first for the full decision record.

⚠️ **This is a hard blocker on #109 (shipping the Saved Object).** Nothing gets distributed to the community until this is cleared. Work it *before* the export step, ideally before authoring the final tile.

> **Note for whoever picks this up:** the specifics of the payload — what it is, exactly which markers identify it, how it was found — were recorded in the **log entries on task #99** during investigation, and are not reproduced here (the tend MCP has no log-read tool, so they could not be copied in). **Read #99's log first.** If the log is thin, treat the identification step below as real work rather than a formality, and write down what you find so this never has to be rediscovered.

## The problem

Hitch's Marvel Champions mod contains **self-replicating Lua** — code that copies itself into other objects. This is a known TTS phenomenon: object scripts that inject themselves into anything spawned, saved, or exported from the table, so a Saved Object authored inside an infected table can carry the payload out with it.

The consequence for us is direct and serious: our importer tile is authored *inside Hitch's table* (it has to be — it clones from bag `7fd666`, so it has to run there). If we build it there and export it, the exported `.json` can contain Lua we did not write, and **we would be the distribution vector**. That's the worst possible outcome for a project whose entire published position is "we redistribute nothing."

## What to do

**1. Identify it precisely.** From #99's log, or by re-deriving: dump the mod's `ObjectStates` JSON and find the payload — which objects carry it, what the Lua does, and what **string markers** identify it (a function name, a distinctive comment, an `onSave`/`onLoad` hook, a `setLuaScript` call, a URL). You need concrete greppable markers, not a general sense of unease.

**2. Author from a clean install.** Write and finalize the tile's Lua **outside** Hitch's table:
   - Keep the Lua in this repo as the source of truth (per #105).
   - Build the Saved Object's `.json` on a clean table — an empty TTS save, or by hand-assembling the JSON — and inject the Lua from the repo file.
   - Use Hitch's table only to *test* the tile, never as the place it gets exported from.
   - If exporting from his table proves unavoidable for some reason, export, then rebuild the JSON from scratch and copy across only the fields we authored.

**3. Scan the published JSON.** An automated check that runs before distribution and fails loudly:
   - Grep the export for every marker from step 1.
   - Assert the only `LuaScript` / `LuaScriptState` present is our own file's contents, byte for byte.
   - Assert no `Custom*` URL fields point at `steamusercontent-a.akamaihd.net` or anything else off-Sanctum (this doubles as the asset-hotlinking check #109 needs).
   - Assert `ContainedObjects` / nested objects are only what we intended.

   Make this a committed script (a mix task, or a test) wired into the packaging step from #109 — not a one-time manual pass. It has to run again on every future re-export.

**4. Verify the shipped artifact behaves.** Spawn the published Saved Object into a **clean** table and confirm it does nothing except exist (no scripts firing, no objects appearing, no `onSave` mutation). Then spawn it into Hitch's table and confirm it still imports correctly.

## Also worth deciding

- Should the install docs (#109) mention this at all? Arguments both ways: transparency about why our tile is safe, versus making an accusation about someone else's mod in our own docs. Lean toward stating what *our* artifact guarantees ("the tile contains only the Lua in this repo, verified by an automated scan before every release") without characterizing his mod. Decide and log it.
- Worth a courtesy mention to Hitch in #110 if he may not know it's in there — but as information, not as an accusation, and only if #99's log supports the finding.

## Acceptance

- Payload identified with concrete string markers, documented on this task (not only in #99's log).
- Tile authored/exported from a clean install; the process documented so it's repeatable.
- Committed scan script, wired into packaging, failing loudly on any foreign Lua or off-Sanctum asset URL.
- Published `.json` passes the scan **and** a manual read-through.
- Clean-table spawn test: the tile is inert until used.

## Depends on / blocks

Depends on #105 (there has to be a tile to export). **Blocks #109** — and therefore the public release.

---

## #113 Custom content: sets, publishing, and discovery

- state: doing

# Custom content: sets, publishing, and discovery

Implements the design settled in task #98. Full design doc:
https://claude.ai/code/artifact/8fb1cead-c5dd-4868-bb12-f466a86874d1

## The core decision

**The published unit moves from the project to the set.** A `HomebrewProject`
becomes a purely private workspace; a new `HomebrewSet` becomes the thing that
carries a name, slug, kind, visibility, version and public URL — the thing that
gets published, reviewed and browsed.

This dissolves the trade that made the feature hard: today a project is both the
creator's workspace *and* the public artifact, so any looseness allowed inside
shows up in the directory, and keeping the browser coherent means restricting how
people organize. Splitting the roles lets the workspace be as free-form as a
Google Drive folder, because nothing outward-facing reads its structure.

## Decisions (all settled)

- **Project → Set → contents.** No waves; homebrew has no release cadence.
- **Set kinds are open data, not an enum** — the `Aspect` lookup pattern
  (`key`/`label`/`origin`/`homebrew_project_id`). Official kinds seeded, creators
  mint their own, nothing validates against a list. Play integration is out of
  scope, so nothing consumes a kind as behavior; it's a label for grouping.
- **Custom sets get their own resource**, not shared with `Catalog.CardSet` —
  that table is a sync-owned MarvelCDB mirror (code-keyed, upserted, admin-only,
  wide-open reads). Browse *rendering* can still share components.
- **Workflow is set-first**: create project → create set → upload into the set.
  The set page is the working surface; the project page is a set index.
- **`homebrew_set_id` is non-null** on `Card`/`CardAlt`/`Aspect`, and
  `homebrew_project_id` is **dropped** from them — one edge, reached through the
  set. This keeps future cross-project moves to a single-column update.
- **Deletion cascades all the way down**, parent sets included. The confirmation
  carries the whole safety burden and must state the blast radius.
- **Creator-scoped slugs**: `/custom/@creator/:slug`. Collisions are structurally
  impossible and attribution is in the URL.
- **Attestation at both** project creation ("allowed to store this") and first
  publish ("allowed to distribute this publicly under my name").
- **Cross-project moves deferred**, but the FK shape stays ready for them.
- **Discovery is two surfaces**: the set directory, and card-level search
  (`origin:` in the pool + a dedicated alt-art gallery). Publishing granularity is
  not browsing granularity.
- **Organization is rewarded, never enforced.** One set called "stuff" with 200
  loose images works and gets a share link — it just lands in "Other" and ranks
  poorly.

## Standing constraints (don't regress)

- Never require metadata beyond the image — the image is the card.
- Private customs must never leak into other users' browse/search surfaces. Any
  `authorize?: false` READ carries an explicit `origin == :official` filter.
- Homebrew writes are user-scoped through policies — never the `authorize?: false`
  system-write paths used by catalog sync.
- Content-addressed homebrew image objects are never deleted or overwritten.
- **Never host bulk-downloadable packs of official card scans; homebrew upload
  must not become a proxy channel for official cards.**
- No monetization on surfaces hosting game IP.
- Never `data-confirm` — use `confirm_button`/`confirm_dialog` (WebKit suppresses
  `window.confirm` in iOS standalone).
- Migrations only via `mix ash.codegen`; Ash resources are the source of truth.
- Synthetic `custom-<uuid>` codes rest on the premise that **full catalog wipes
  are retired as a maintenance technique** — don't reintroduce one.

## Phases

1. **Model** (subtasks 1–5) — sets, kinds, FK re-point, policy re-point, cleanup.
   No visible change.
2. **Set workspace** (6–9) — the structural UI move; the set page becomes where
   work happens.
3. **Publish & directory** (10–14) — slugs, publish flow, public surfaces. **Admin
   gate lifts at the end of this phase.**
4. **Card-level discovery** (15–17) — `origin:` search, alt-art gallery, art
   preference.
5. **Versioning & review** (18) — designed for, deliberately last.

## Related top-level tasks

Split out of the old roadmap rather than made subtasks — they're independent of
the set redesign:

- **Google Drive import** — the acquisition path that meets creators where they
  actually are.
- **Friendly referential integrity for cards used in decks** — dormant now; set
  deletion makes it urgent once custom cards are deck-selectable.
- **Custom aspects, phase 2** — the creator-facing half of the aspect refactor.
- **Bulk vision enrichment: extract-all per set.**
- **Deferred ecosystem + play integration** (`someday`) — TTS export, Card Maker
  import, export API, print sheets, scenario/deckbuilder slices.

## Remaining open questions

- Nesting depth — recommend capping at one level, since cascade makes blast radius
  a recursive walk otherwise.
- Username changes break published set URLs (cost of creator-scoped slugs) —
  claim-once, or stored redirects. Settle before the first public link.
- Non-Marvel conversions in the public directory.
- Storage quotas per creator.
- Ambition: personal-plus vs. THE community hub — the hub path means courting the
  Homebrew Discord / Hall of Heroes early.

---

## #114 1. Add SetKind lookup resource + seed official kinds

- state: done
- parent: #113

# 1. Add SetKind lookup resource + seed official kinds

**Phase 1 (model). No dependencies — start here.**

## Context

A set's *kind* labels what it contains (hero, scenario, modular, aspect, player
cards, alt art, campaign). It must be **creator-extensible, not a closed enum**:
play integration is out of scope, so nothing in the app consumes a kind as
behavior — it is purely a grouping and filter label. Restricting it to FFG's
taxonomy would stop creators making things FFG never shipped, which is against
the project's "validation, not restriction" line.

This is the same enum → lookup-resource move `Sanctum.Games.Aspect` already made
(commits `217bcd21`, `68b26590`; vault plan
`plans/2026-07-23-aspect-as-resource.md`). Copy the shape, but see the identity
warning below — it does **not** copy directly.

## Work

- New `Sanctum.Homebrew.SetKind`, table `set_kinds`.
- Attributes: `key` (string), `label`, `sort_order` (default 100), `origin`
  (`Sanctum.Games.CardOrigin`, default `:official`), nullable
  `homebrew_project_id`.
- Seed official kinds: `hero`, `scenario`, `modular`, `aspect`, `player_cards`,
  `alt_art`, `campaign`, `other`.
- Policies mirroring the `CardAlt` origin split: reads — official always, custom
  published-or-own; mutations — creator-scoped for custom, admin for official.
- Domain wrappers in `Sanctum.Homebrew` for list/create.

## Watch out

**`Aspect` uses `key` as the primary key. Don't copy that here.** Official
aspects are globally unique, but set kinds are *project-scoped* — two creators
must both be able to invent "Hazard Deck". Use a UUID primary key with a unique
identity on `(key, homebrew_project_id)`, so official kinds (null project) stay
globally unique while custom keys only need to be unique within their project.

## Acceptance criteria

- [ ] Migration generated by `mix ash.codegen`; no hand-written SQL.
- [ ] Official kinds are seeded and readable by an anonymous (nil) actor.
- [ ] A creator can mint a project-scoped kind; another user's read never returns
      it, and a nil-actor read never returns it.
- [ ] Two different projects can each define the same `key` without collision.
- [ ] No code path validates a kind string against a fixed list.
- [ ] `mix ck` clean.

---

## #115 2. Add HomebrewSet resource with policies and domain actions

- state: done
- parent: #113

# 2. Add HomebrewSet resource with policies and domain actions

**Phase 1 (model). Depends on #1 (SetKind).**

## Context

The set is the unit that gets published, reviewed, versioned and browsed — the
central change in this whole effort. `HomebrewProject` becomes a private
workspace; `HomebrewSet` becomes the public artifact. Nothing consumes this
resource yet; it lands additively so later tasks can re-point onto it.

## Work

New `Sanctum.Homebrew.HomebrewSet`, table `homebrew_sets`:

| Field | Notes |
|---|---|
| `homebrew_project_id` | required, `on_delete: :delete` |
| `creator_id` | **denormalized from the project** — see below |
| `name`, `slug` | slug column only; generation is #10 |
| `description`, `banner_url` | markdown description |
| `set_kind_key` | nullable FK — unclassified is a legal state |
| `visibility` | `:private \| :unlisted \| :published`, default `:private` |
| `maturity` | `:draft \| :beta \| :complete`, default `:draft` |
| `tags` | `{:array, :string}` |
| `parent_set_id` | nullable self-ref, `on_delete: :delete` |
| `attestation` | boolean, for the publish-time claim (#11) |

Aggregates: `card_count`, `alt_count`.

Actions: `create`, `update`, `set_visibility` (kept separate from general editing
so the publish flow can hang off one action), `destroy`, `for_creator`,
`by_project`.

**Why `creator_id` is denormalized:** the content read policies (#4) filter on
the set's creator on every card read. Routing through the project would put a
second join in that filter.

## Watch out

**Keep the read policy's OR branches as separate `authorize_if` checks.** An
`expr` referencing `^actor(:id)` collapses to false *wholesale* under a nil
actor, which would hide published sets from anonymous reads. This is documented
at the existing `HomebrewProject` policy site — read it before writing this one.

## Acceptance criteria

- [ ] Resource + migration via `mix ash.codegen`.
- [ ] A new set defaults to `:private`.
- [ ] Creator can create/read/update/destroy their own sets.
- [ ] Another user's set reads as **not-found**, not forbidden.
- [ ] An anonymous read returns published sets and does **not** collapse to empty
      — with an explicit regression test for the nil-actor gotcha.
- [ ] `creator_id` is derived from the project on create, never user-supplied.
- [ ] `parent_set_id` carries `on_delete: :delete`.
- [ ] `mix ck` clean.

## Plan

**Goal.** **This task is already implemented and shipped as PR #359** —
https://github.com/jwstover/sanctum/pull/359 (branch `homebrew-sets`, stacked on
`homebrew-set-kinds`/#358, CI green, MERGEABLE/CLEAN). **There is nothing to
build.** This step verifies the shipped work against the acceptance criteria and
closes the task. Do not write code.

**Done when.**
- `git diff --stat homebrew-sets HEAD -- lib/sanctum/homebrew/homebrew_set.ex lib/sanctum/homebrew/changes lib/sanctum/homebrew/validations priv/repo` is empty.
- `gh pr view 359` reports `mergeStateStatus: CLEAN` with "Build and test" and "Formatting, Credo, and Unused Deps" SUCCESS.
- The PR link is recorded on the task and the task state is `done` (matching sibling task #114, which is `done` with its PR #358 still open).

**Files.** All already exist on `homebrew-sets` — read to verify, do not edit.
- `lib/sanctum/homebrew/homebrew_set.ex` — the resource: attributes, 4 `references`, actions `create`/`update`/`set_visibility`/`destroy`/`for_creator`/`by_project`, policies.
- `lib/sanctum/homebrew/changes/set_creator_from_project.ex` — stamps `creator_id` server-side.
- `lib/sanctum/homebrew/validations/{parent_set_in_same_project,set_kind_in_same_project}.ex`
- `priv/repo/migrations/20260904143300_add_homebrew_sets.exs` + snapshot — generated by `mix ash.codegen add_homebrew_sets`.
- `test/sanctum/homebrew/homebrew_set_test.exs` — 31 tests covering all 8 criteria.
- `lib/sanctum/homebrew.ex` — domain wrappers `create_set`, `update_set`, `set_set_visibility`, `destroy_set`, `get_set`, `list_my_sets`, `list_project_sets`.

**Steps.**
1. Run the scoped `git diff --stat` above; confirm empty. (A broader diff over `lib/sanctum/homebrew` also shows `content_type.ex` and `alt_art_test.exs` — those belong to the unrelated `homebrew-alt-art-wizard` branch in the shared workspace. Ignore them; do not touch them.)
2. Run `gh pr view 359 --json mergeStateStatus,statusCheckRollup,isDraft` and confirm green.
3. Read `lib/sanctum/homebrew/homebrew_set.ex:137-167` and confirm the read policy keeps `visibility == :published` and `creator_id == ^actor(:id)` as **two separate `authorize_if` lines**.
4. Append the PR URL to this task body; set task state `done`.

**Out of scope.** Do not edit `homebrew_set.ex` or any file on `homebrew-sets`. Do not add the `card_count`/`alt_count` aggregates. Do not rename `set_kind_id` to `set_kind_key`. Do not merge, rebase or re-push #359 or #358. Do not open a new PR or branch. Do not commit the unrelated uncommitted `demos/`, `AUTH_ROADMAP.md` or `router.ex` changes sitting in the workspace — they belong to another agent.

**Decisions.** Two places where the task body above is stale and the shipped code is right — do not "fix" either:
- Body says `set_kind_key` FK; code uses a uuid `set_kind_id` belongs_to. Correct: `SetKind.key` is only unique per project (task #1's identity is `(key, homebrew_project_id)`), so a key-based FK is impossible.
- Body lists `card_count`/`alt_count` aggregates; the PR defers them. Correct and unavoidable: they aggregate over `Card.homebrew_set_id` / `CardAlt.homebrew_set_id`, columns that do not exist until task #3 (id 116) adds them. Neither aggregate is in this task's acceptance-criteria checklist.
- All 8 acceptance criteria are met. Verified directly: the nil-actor regression asserts `ids(Ash.read!(HomebrewSet, actor: nil)) == [pub_id]`, and the creator_id test asserts a `force_change_attribute(:creator_id, other.id)` is still overwritten by the stamp.

**Verify.** CI on PR #359 is the verifier of record — build/test and format/Credo both SUCCESS there. Local `mix test` and `mix ck` cannot run in this environment: Postgres is not listening on `localhost:5432` (`docker compose ps` shows no containers). If you want a local run, `docker compose up -d` first, then `mix test test/sanctum/homebrew/homebrew_set_test.exs` — optional, not required. No tests to add.

**Ship.** GitButler workspace: yes. Merge target: `main` (via the stack: `homebrew-sets` → `homebrew-set-kinds` → `main`). Base it on: `homebrew-set-kinds` (already done). Branch: `homebrew-sets` (already exists, local == origin). Forge: github (CLI: `gh`). PR title: `feat(homebrew): add HomebrewSet resource with policies and domain actions` — **PR #359 already open; do not create another.**

## PR

https://github.com/jwstover/sanctum/pull/359

## Implementation

Verification-only step — no code written. Confirmed PR #359 (branch `homebrew-sets`) already contains the full implementation: `homebrew_set.ex`, `changes/set_creator_from_project.ex`, `validations/{parent_set_in_same_project,set_kind_in_same_project}.ex`, migration+snapshot, `homebrew.ex` domain wrappers, and `homebrew_set_test.exs` (single commit `9521e41c`). Local `homebrew-sets` ref matches `origin/homebrew-sets`. CI green: `mergeStateStatus: CLEAN`, "Build and test" and "Formatting, Credo, and Unused Deps" both SUCCESS. Read policy at lines 149-152 keeps `visibility == :published` and `creator_id == ^actor(:id)` as two separate `authorize_if` checks, per the nil-actor gotcha. `card_count`/`alt_count` aggregates and `set_kind_key` rename are deliberately deferred/rejected per the plan's Decisions — left for task #116 and out of scope here. Set state to `done` per the plan's done-when (deviates from generic step boilerplate's "review" — plan cites sibling #114 precedent).

---

## #116 3. Point Card/CardAlt/Aspect at sets (add FK, backfill, non-null)

- state: review
- parent: #113

# 3. Point Card/CardAlt/Aspect at sets (add FK, backfill, non-null)

**Phase 1 (model). Depends on #2.**

## Context

Custom content currently hangs off `homebrew_project_id`. It needs to hang off
the set instead, because the set is what gets published. The FK is **non-null**:
uploads always happen inside a set (#6), so there is no unsorted limbo to model —
no orphan bucket to render, and no "cards with no set" branch in any query.

Policies still filter on the *project* after this task; re-pointing them is #4.
That keeps the risky change isolated.

## Work

1. **Backfill sets**: one `HomebrewSet` per existing `HomebrewProject`,
   inheriting the project's `name`, `visibility`, `maturity` and `tags`, with
   `creator_id` from the project.
2. Add nullable `homebrew_set_id` to `Card`, `CardAlt` and `Aspect`, each with
   `on_delete: :delete`.
3. Backfill each row from its `homebrew_project_id`.
4. Set the column NOT NULL.
5. Update `create_custom`, `create_alt_art`, `declare_custom` and the custom
   `Aspect` create to accept and require `homebrew_set_id`.

Leave `homebrew_project_id` in place — it is dropped in #5.

## Acceptance criteria

- [ ] Every existing custom `Card`, `CardAlt` and `Aspect` row has a set after
      migration; zero nulls.
- [ ] Column is NOT NULL at the database level.
- [ ] Creating a custom card without a set fails validation with a clear message.
- [ ] Cascade verified by test: destroying a set removes its cards, alts and
      aspects.
- [ ] Existing homebrew tests pass **unchanged** — policies are untouched here.
- [ ] No visible UI change.
- [ ] `mix ck` clean.

## Plan

**Goal.** Give every custom `Card`, `CardAlt` and `Aspect` a required `homebrew_set_id` (FK → `homebrew_sets`, cascade delete), backfill one set per existing project, and make the custom create paths carry a set. Policies stay project-based (#4); `homebrew_project_id` stays (#5).

**Done when.**
- After migrating, `SELECT count(*) FROM cards|card_alts|aspects WHERE origin='custom' AND homebrew_set_id IS NULL` returns 0 on the dev DB (run `scripts/pull_prod_db` first if you can, so the backfill touches real rows).
- New check constraints `cards_origin_set_consistency`, `card_alts_origin_set_consistency` and `aspects_origin_set_consistency` (`(origin = 'official') = (homebrew_set_id IS NULL)`) exist in Postgres.
- `Card :create_custom` / `CardAlt :create_custom` without `homebrew_set_id` return Invalid with "must belong to a set". A set from another project returns "must be a set in the same project".
- New test: `Homebrew.destroy_set` removes that set's cards (and their sides), alts and aspects.
- Project page uploads (cards and alt art) still work on a brand-new project, with no UI change. All test assertions are untouched; only setups change.

**Files.**
- `lib/sanctum/games/card.ex`, `card_alt.ex`, `aspect.ex`: add `belongs_to :homebrew_set` (allow_nil? true), add `reference :homebrew_set, on_delete: :delete, index?: true` and the new check constraint (keep the existing project constraint). Add `:homebrew_set_id` to the accept lists of `Card.create_custom`, `CardAlt.create_custom` and `Aspect.create`.
- `lib/sanctum/homebrew/validations/set_in_same_project.ex` (new): mirrors `ParentSetInSameProject`. The changeset's `homebrew_set_id` must name a set whose `homebrew_project_id` equals the changeset's.
- `lib/sanctum/homebrew/homebrew_set.ex`: add `has_many :cards`, `:card_alts`, `:aspects` and replace the "arrive with task #3" comment. No aggregates.
- `lib/sanctum/games/changes/declare_alt_art.ex:103`, `revert_alt_art.ex:40`, `unpair_custom_card.ex:43`: copy `homebrew_set_id` from the source row next to `homebrew_project_id`. `create_custom_alt_art.ex` needs nothing because the set is an accepted attribute.
- `lib/sanctum/homebrew.ex`: new `ensure_project_set(project, actor)`. It returns the project's oldest set (`list_project_sets`, sorted by `inserted_at`), or creates one through `create_set` with the project's name/maturity/tags and the actor. Update the docs on `create_custom_card` / `create_alt_art`.
- `lib/sanctum_web/live/homebrew_live/show.ex` (~:123 and ~:201): call `ensure_project_set` at upload time, not in mount, and pass `homebrew_set_id`.
- `priv/repo/migrations/`: two codegen migrations plus one hand-written data migration (step 3).

**Steps.**
1. Add the attributes and references to the 3 resources (no constraints yet), then run `mix ash.codegen add_homebrew_set_fk`.
2. Add a hand-written data migration `<A+1s>_backfill_homebrew_set_ids.exs`. Copy the shape and the "deliberate exception" moduledoc from `20260710172820_backfill_game_card_game_id.exs`.
   - `INSERT INTO homebrew_sets (id,name,visibility,maturity,tags,creator_id,homebrew_project_id)` with `SELECT uuid_generate_v7(), p.name, p.visibility, p.maturity, p.tags, p.creator_id, p.id FROM homebrew_projects p WHERE NOT EXISTS (a set for p)`.
   - Then one `UPDATE … SET homebrew_set_id` per table. Pick the oldest set per project (`DISTINCT ON (homebrew_project_id) … ORDER BY inserted_at, id`), filtered to `homebrew_project_id IS NOT NULL AND homebrew_set_id IS NULL`.
   - `down` is a no-op.
3. Add the 3 `check_constraint`s, then run `mix ash.codegen require_homebrew_set_on_custom_content`. Its timestamp must sort after step 2's.
4. Add validations:
   - On `Card.create_custom` and `CardAlt.create_custom`: `validate present(:homebrew_set_id, message: "must belong to a set")` (plain, so it fails before policies), plus `validate SetInSameProject, before_action?: true`.
   - On `Aspect.create`: the same two with `where: [attribute_equals(:origin, :custom)]`. Official seeds in `release.ex` still pass.
5. Make the 3 change-module copies, add `ensure_project_set`, and update `show.ex`.
6. Tests. In setups that call `create_custom_card` / `create_alt_art` directly, add `set = Homebrew.ensure_project_set(project, actor)` and pass `homebrew_set_id: set.id`. The files: `test/sanctum/homebrew/{custom_card,alt_art,card_privacy,homebrew_project}_test.exs`, `test/sanctum_web/live/{homebrew_live/show,homebrew_live/edit_card,card_live/detail}_test.exs`. Grep for any others. Change no assertions.
7. New tests in `test/sanctum/homebrew/homebrew_set_test.exs`:
   - Missing set gives Invalid.
   - Cross-project set gives Invalid.
   - A non-owner passing their own project with someone else's set still gets an error.
   - Cascade: create a card, a declared alt and an admin-created custom aspect in a set, destroy the set, and assert all three are gone, side rows included.
   - Declare, revert and unpair keep the set.

**Out of scope.** Policies (#4). Dropping `homebrew_project_id` or its constraints (#5). Set-picker UI, `card_count` aggregates and moving cards between sets (#6+). `PairCustomCard`'s same-project check (leave it). Editing PR #340's code beyond the call sites above. The pre-existing red test.

**Decisions.**
- **Literal NOT NULL is impossible.** These tables hold official rows (the seeded aspects, the official reprints), so the column stays nullable. The DB-level guarantee is the origin↔set check constraint, the same pattern as the project FK. Read the "NOT NULL" acceptance criterion this way.
- **The set is derived, not accepted, for `declare_custom` / revert / unpair.** They convert a row in place, so they inherit the source's set. Adding it as an input would only add a smuggling surface.
- **Projects get a set lazily at upload time** (`ensure_project_set`), not through an after_action on project create. An after_action would break the exact-list assertions in `homebrew_set_test.exs:245`. This is a bridge until #6 adds a real set picker.
- **Keep the domain functions strict, with no defaulting.** So there is no unsorted limbo, and test setups do change.
- **`SetInSameProject` uses `before_action?`** so a non-owner gets Forbidden and not an Invalid that would reveal existence, same reasoning as `ParentSetInSameProject`.
- Backfilled sets inherit name/visibility/maturity/tags/creator and get `attestation` false, since the publish gate is later work.

**Verify.** build `mix compile --warnings-as-errors`, migrations `mix ash.codegen --check` and `mix ecto.migrate` on dev plus the zero-null query, test `mix test`, lint `mix ck`. **Baseline is red:** 1 failure (`test/sanctum_web/live/homebrew_live/show_test.exs:61`, "Alt art" chooser), which comes from PR #340 itself and also fails in its CI. Leave it. Estimated diff is ~350 lines excluding generated migrations and snapshots.

**Ship.** GitButler workspace: yes. Never run bare `but push`. The `zz` lane holds unrelated uncommitted files (`demos/`, `AUTH_ROADMAP.md`, `router.ex`, a roadmap deletion), so stage only your hunks and review before committing. Merge target: `main`. Base it on: `homebrew-alt-art-wizard` (PR #340; it owns `CardAlt :create_custom` / `Homebrew.create_alt_art`). Stack the new branch on it and open the PR against it. Branch: `homebrew-set-fk`. Forge: github (CLI: gh). PR title: `feat(homebrew): point custom cards, alts and aspects at sets`

## PR
https://github.com/jwstover/sanctum/pull/409

## Implementation
Built per plan: `homebrew_set_id` FK (cascade) on cards/card_alts/aspects, `*_origin_set_consistency` check constraints, hand-written backfill migration, `SetInSameProject` validation, set inheritance in declare/revert/unpair, `Homebrew.ensure_project_set/2` used by the project page uploads, and new tests in `homebrew_set_test.exs`. PR: https://github.com/jwstover/sanctum/pull/409 (stacked on `homebrew-alt-art-wizard`).
Deviations: `present` has no `:message` option, so I used its `do message ... end` form; `ParentSetInSameProject.same_project?/2` is now public and shared (ExDNA flagged a clone); the plan's declare_alt_art `:103` site turned out to be only the one change at line ~40.
Dev DB has 0 custom rows with a NULL set; I did not run `scripts/pull_prod_db`.
CI: the only failing test is the pre-existing `homebrew_live/show_test.exs:62` "Alt art" chooser failure from #340, which the plan said to leave. So the build job is red.

## Follow-up: #340 red test fixed
The "Alt art" chooser failure (`homebrew_live/show_test.exs:62`) happened because the chooser renders the file pickers only when the S3 env vars are set (`HomebrewImages.configured?/0`), and CI doesn't set them. The fix is commit `lok` on `homebrew-alt-art-wizard`. The async test now covers the "not configured" notice, and a new sync module `show_uploads_test.exs` sets and restores the env vars to test the configured chooser. Full suite: 990 tests, 0 failures. `mix ck` is clean. Not pushed yet.

Pushed the stack. Another process in the workspace then rebased it onto main v1.95.0 and pushed it again. CI is green on both #340 (`8badb038`) and #409 (`83e3f2c3`).

---

## #117 4. Re-point read policies from project to set

- state: review
- parent: #113

# 4. Re-point read policies from project to set

**Phase 1 (model). Depends on #3. This is the risky one — isolate it.**

## Context

Privacy is enforced by **filter** read policies, so other people's unpublished
work is *invisible* rather than forbidden. Those filters currently key on
`homebrew_project.creator_id` and the project's visibility. Both move to the set.

The mechanism does not change — only the expression each policy filters on.

## Work

- `Card`, `CardSide`, `CardAlt`, `Aspect` read policies become three **separate**
  `authorize_if` branches:
  - `origin == :official`
  - `homebrew_set.visibility == :published`
  - `homebrew_set.creator_id == ^actor(:id)`
- `HomebrewProject` read narrows to creator-only (plus admin bypass) — it is a
  workspace now.
- Keep every `authorize?: false` read pinned to `origin == :official`: the
  writeup resolver, signature cards, and `CardAlt.by_code` / `by_codes`.
- Port the whole existing leak suite onto the set-based filter.

## Watch out

- **Separate `authorize_if` branches, not one combined `expr`** — an `expr`
  referencing `^actor(:id)` collapses to false wholesale under a nil actor, which
  would hide *published* content from anonymous reads (guess game, game setup,
  public card pool).
- On creates, policies run **before** `before_action` hooks, so a create-time
  ownership check must resolve action *arguments*, not changeset attributes.

## Acceptance criteria

- [ ] Leak tests green for every read path: browse + counts, guess game
      (actor-less), get-by-id, by-code, by-set, writeup resolution, deck
      rendering.
- [ ] A private set's cards are invisible to another signed-in user **and** to a
      nil actor.
- [ ] A published set's cards are visible to a nil actor — explicit regression
      test for the nil-actor collapse.
- [ ] `HomebrewProject` is not readable by a non-creator, non-admin.
- [ ] No `authorize?: false` read path returns a custom row — asserted by test,
      not by inspection.
- [ ] `mix ck` clean.

## Plan

**Goal.** Make custom-content privacy follow the **set**, not the project. Card, CardSide, CardAlt and Aspect read filters, plus the custom ownership checks, change from `homebrew_project.*` to `homebrew_set.*`. `HomebrewProject` becomes readable only by its creator (admins still bypass). After this, #5 can drop `homebrew_project_id` without breaking any policy. This is policy-only: no migrations.

**Done when.**
- A **published project with a private set** keeps its cards, sides and alts hidden from another user and from a nil actor. This is the test that proves the re-point happened.
- A **private project with a published set** shows its cards to a nil actor through browse, `Ash.get` and by-set. This is the nil-actor regression test.
- `Homebrew.get_project/2` on a published project returns `{:error, %Ash.Error.Invalid{}}` for other users and for nil.
- With the set **published**, tests assert that the writeup resolver, `Decks.signature_cards/1`, `CardAlt` by_code/by_codes and `Search.Values.traits/0` return no custom row.
- `mix test` and `mix ck` are green, and `mix ash.codegen --check` reports no changes.

**Files.**
- `lib/sanctum/games/card.ex:238-251`: change the read branches to `homebrew_set.visibility == :published` and `homebrew_set.creator_id == ^actor(:id)`. In the update/destroy/pair/unpair filter, use `homebrew_set.creator_id`. Swap the `create_custom` check to `ActorOwnsSet`.
- `lib/sanctum/games/card_side.ex:150-152`: change the read branches to `card.homebrew_set.visibility` and `card.homebrew_set.creator_id`.
- `lib/sanctum/games/card_alt.ex:158-168`: change the read branch to `homebrew_set.visibility == :published`, but **keep** `creator_id == ^actor(:id)`. Swap the `create_custom` check to `ActorOwnsSet`. Fix the moduledoc line 17 ("follows the project").
- `lib/sanctum/games/aspect.ex:103-107`: replace `authorize_if always()` with the three separate branches (`origin == :official`, `homebrew_set.visibility`, `homebrew_set.creator_id`) and rewrite the "Phase 1" comment.
- `lib/sanctum/homebrew/homebrew_project.ex:85-92`: drop the `visibility == :published` branch, keep `creator_id == ^actor(:id)`, and update the comment ("private workspace").
- `lib/sanctum/homebrew/checks/actor_owns_set.ex` (new): a SimpleCheck modelled on `actor_owns_project.ex`. It resolves the accepted `homebrew_set_id` **attribute** with an `authorize?: false` `Ash.get(HomebrewSet, …)` and compares `set.creator_id == actor.id`. A nil actor or missing set gives false.
- `lib/sanctum/homebrew/checks/actor_owns_source_card.ex`: load `:homebrew_set` instead of `:homebrew_project` and compare `card.homebrew_set.creator_id`. It keeps reading the `:source_card_id` **argument**.
- `lib/sanctum_web/live/deck_live/new.ex:79-81` (`sets_with_alter_ego`) and `lib/sanctum/decks/validations/validate_hero.ex:59-62` (`set_has_alter_ego?`): add `origin == :official` to the filter. Both are unpinned `authorize?: false` Card reads. They are harmless today only because customs have `set: nil`. Both are private functions, so these pins are checked by inspection; no test.
- `lib/sanctum/search/values.ex:24` (`traits/0`): this raw SQL skips policies, so traits from private customs leak into the public autocomplete. Change it to join `cards` on `card_sides.card_id` and keep only `cards.origin = 'official'`. It must stay a literal string, which Sobelow checks.
- Update the `lib/sanctum/homebrew.ex` moduledoc (lines ~11-15) so it says privacy follows the set.

**Steps.**
1. Add `ActorOwnsSet` and re-point `ActorOwnsSourceCard`. Then edit the five resource policy blocks above. Each branch stays its own `authorize_if`; never combine them into one `or` expr.
2. Pin the three unpinned reads (`new.ex`, `validate_hero.ex`, `search/values.ex`).
3. Port these publish sites from `Homebrew.set_project_visibility!(project, :published, …)` to `Homebrew.set_set_visibility!(set, :published, actor: creator)` (the set is the one from `ensure_project_set`): `card_privacy_test.exs:33`, `alt_art_test.exs:303`, `card_live/detail_test.exs:164`. Flip `homebrew_project_test.exs:64` to assert `{:error, %Ash.Error.Invalid{}}` for other and nil, and rename it. Leave `set_kind_test.exs:245/254` alone (SetKind stays project-keyed).
4. Add the tests in Verify. Run `mix test test/sanctum/homebrew test/sanctum_web/live/card_live` until green, then the full suite, `mix ash.codegen --check` and `mix ck`.

**Out of scope.**
- **SetKind** (`set_kind.ex:109-124`) stays keyed on `homebrew_project.visibility`. It has no set FK and the task doesn't name it. **Flag for #5:** dropping `HomebrewProject.visibility` breaks this expression and needs a design answer, e.g. `exists(sets, visibility == :published)`.
- `ActorOwnsProject` stays on `HomebrewSet` create and on `SetKind.create_custom`, because those really do target a project.
- `SetInSameProject`, `homebrew_project_id` columns and constraints, `list_project_cards` / `list_project_alts` (homebrew.ex:92/215), `PairCustomCard`'s same-project check, `HomebrewLive.Show`/`EditCard` lacking a creator check (the routes are admin-gated; #6 redoes them): all of these belong to #5 or later.
- `Card.by_code`/`CardSide.by_code` have no origin pin, but they run under policy, which is enough.
- `card_vision/eval.ex:99,108` is unpinned on purpose (its comment says so).
- The admin count stats and the raw SQL in `decks/stats.ex` and `export_deck_corpus` only cover published decks or admin/offline use.
- `new.ex:63` and `uniqueness.ex:142` load `Hero → card`, which is an official catalog FK.

**Decisions.**
- **CardAlt keeps its own denormalized `creator_id`** in its creator branch and in the revert/destroy filter, instead of `homebrew_set.creator_id`. That avoids a join and the column already exists. This deliberately deviates from the task text, and only for this resource.
- **The create check reads the accepted `homebrew_set_id` attribute.** It is accepted input, so policies can see it. Only values set in `before_action` hooks would be invisible to them. `SetInSameProject` still guarantees the set and project agree.
- Nothing in `lib/sanctum_web` loads `:homebrew_project` for a non-creator. The project lookups in checks and validations (`ActorOwnsProject`, `SetCreatorFromProject`, `*InSameProject`) use `authorize?: false`, so narrowing the project read breaks nothing, and there is no UI change.
- Aspect has no domain create path for customs. Tests create them with `Ash.create!(Aspect, %{origin: :custom, …}, authorize?: false)`, following `homebrew_set_test.exs:529`, and read them via `Games.list_aspects!` (it has no lib callers, which is fine).

**Verify.** build `mix compile --warnings-as-errors`, codegen `mix ash.codegen --check`, test `mix test`, lint `mix ck`. Baseline on the workspace: 990 tests, 0 failures, and `mix ck` is clean. PR #409's CI build job shows red. Run `test/sanctum_web/live/homebrew_live/show_test.exs` on the new branch first, and don't assume any failure there is pre-existing.

Tests to add in `test/sanctum/homebrew/card_privacy_test.exs`, in a new `describe "set-keyed visibility"`:
- The published-project/private-set case and the private-project/published-set case above. Cover browse with counts, `Ash.get`, `get_cards_by_set!`, `list_card_sides_by_codes!`, and alts loaded through `load: [:alts]`.
- A custom Aspect is hidden from other users and nil and visible to its creator. Once its set is published, nil can see it.
- Deck rendering: seed a `DeckCard` with `authorize?: false` that points at the private custom card from another user's published deck. Then call `Sanctum.Decks.get_deck(id, actor: other/nil, load: [deck_cards: [card: :primary_side]])` and assert that the custom card is absent.

Add a new module `test/sanctum/homebrew/system_read_pinning_test.exs` with `async: false`, because `Search.ValueCache` is global; call `ValueCache.reset()` in setup. Publish the set, then assert that none of these resolve the custom card:
- a `Writeup.render` link to it;
- `Decks.signature_cards/1`, after giving the custom card the hero's `set` with `authorize?: false`;
- `Games.get_card_alt_by_code` and `list_card_alts_by_codes!`;
- `Search.Values.traits/0`, after giving the custom side a unique trait.

In `homebrew_set_test.exs`: `create_custom` with your own project id and someone else's set id returns Forbidden or Invalid, never `{:ok, _}`.

**Ship.** GitButler workspace: yes. Never run bare `but push`; push with `but push homebrew-set-policies`. The `zz` lane holds unrelated uncommitted files (`demos/`, `AUTH_ROADMAP.md`, `router.ex`, `demo_auth_controller.ex`, a roadmap deletion), so stage only your own hunks and review them before committing. Merge target: `main`. Base it on: `homebrew-set-fk` (PR #409, which stacks on #340). Stack on that branch and open the PR against `homebrew-set-fk`. Branch: `homebrew-set-policies`. Forge: github (CLI: gh). PR title: `feat(homebrew): key custom-content read policies on sets`

## PR
https://github.com/jwstover/sanctum/pull/414

## Implementation
Policies re-pointed to sets (Card, CardSide, CardAlt, Aspect); HomebrewProject creator-only; new ActorOwnsSet; pinned deck new / validate_hero / Search.Values.traits to official. Tests in card_privacy_test, new system_read_pinning_test, homebrew_set_test.
Deviations: #409/#340 were already merged to main, so PR targets `main` (rebased via `but pull`). Existing "another project's set is Invalid" tests now accept Forbidden too, since ActorOwnsSet rejects first.
Left for #5: SetKind still keys on homebrew_project.visibility.

---

## #118 5. Drop the project FK and trim HomebrewProject

- state: todo
- parent: #113

# 5. Drop the project FK and trim HomebrewProject

**Phase 1 (model). Depends on #4 — only safe once nothing reads the project FK.**

## Context

With a non-null set FK, `homebrew_project_id` on content is redundant: the
project is reachable through the set. Keeping both would mean two columns that
can disagree, policed by a check constraint.

Dropping it also keeps **future cross-project moves** cheap (deferred, but wanted
eventually): with one edge, moving a set to another project is a single-column
update on the set and every card follows. With two edges, every move becomes a
multi-row transaction that has to keep columns in sync.

`HomebrewProject` also sheds everything outward-facing, since it is now purely a
private workspace.

## Work

- Drop `homebrew_project_id` from `Card`, `CardAlt` and `Aspect`.
- Re-point the origin check constraint from project provenance to **set**
  provenance (`origin == :custom` iff `homebrew_set_id` present).
- Drop `visibility`, `content_types`, `maturity`, `tags` and `banner_url` from
  `HomebrewProject`.
- Remove `Sanctum.Homebrew.ContentType` if nothing else uses it.
- Rewrite `Sanctum.Homebrew.list_project_cards/2` to join through sets.

## Acceptance criteria

- [ ] `grep -rn "homebrew_project_id" lib/sanctum/games` returns nothing.
- [ ] Check constraint enforces `origin == :custom` ⟺ `homebrew_set_id` present.
- [ ] `ContentType` is deleted, or a comment records why it was kept.
- [ ] Full test suite green.
- [ ] `mix ck` clean.

---

## #119 6. Set workspace LiveView; project page becomes a set index

- state: todo
- parent: #113

# 6. Set workspace LiveView; project page becomes a set index

**Phase 2 (set workspace). Depends on #5. The structural move.**

## Context

Today `SanctumWeb.HomebrewLive.Show` (`/homebrew/:id`, ~777 lines) is the single
content-and-upload surface for a project. Under the set-first workflow the
creator makes a project, makes a set, and uploads **into that set** — so the
working surface moves down one level and the project page becomes a light index.

Net effect: `HomebrewLive.Show` gets substantially *smaller*, rather than growing
a second job.

## Work

- New route `/homebrew/:project_id/sets/:set_id` → `HomebrewLive.SetShow`.
- Move out of `HomebrewLive.Show`: the upload chooser, the card grid, the alt-art
  "to assign" strip and assign sheet (with the `AltSearchNav` keyboard hook), and
  pair mode.
- `HomebrewLive.Show` becomes a set index: sets with their counts, plus an inline
  create-set form.
- The card editor's back link becomes set-aware.
- Reuse the existing `SanctumWeb.HomebrewLive.Support` and
  `SanctumWeb.HomebrewComponents` extractions rather than duplicating.
- The chooser's copy narrows to **Card / Alt art** — a question about card
  *shape*, not content type, since the set now carries the kind.

## Watch out — do not regress this

The upload chooser's options **are** the file pickers: each is a `<label>`
wrapping a hidden `auto_upload` `live_file_input`, so choosing a type opens the
OS dialog **in the same click**. A browser file dialog cannot survive a
navigation. This design was revised twice to land here (see
`CUSTOM_CONTENT_ROADMAP.md` §0). Do **not** reintroduce a flow where choosing a
type navigates before the picker opens, and do not split the types onto separate
pages.

## Acceptance criteria

- [ ] Create project → create set → upload works end to end against the dev
      server at `localhost:4150` (verify with playwright-cli).
- [ ] Choosing a type in the chooser opens the OS file dialog in the same click,
      with no intermediate navigation or second "click the input" step.
- [ ] Uploaded cards land in the viewed set; alt images land in that set's
      to-assign strip.
- [ ] The project page has **no** upload affordance.
- [ ] Pair mode, the assign sheet and its keyboard navigation all work on the set
      page.
- [ ] `HomebrewLive.Show` is meaningfully shorter than before.
- [ ] `mix ck` clean.

---

## #120 7. Set metadata editing + open kind combobox

- state: todo
- parent: #113

# 7. Set metadata editing + open kind combobox

**Phase 2 (set workspace). Depends on #6.**

## Context

A set needs the metadata that will drive its directory tile and public page:
name, description, banner, tags, maturity and kind. The kind picker is where the
"validation, not restriction" principle becomes visible — it suggests, never
constrains.

## Work

- Edit a set's `name`, `description` (markdown), `banner_url`, `tags` and
  `maturity`.
- Kind combobox: seeded `SetKind` rows as suggestions; free text mints a new
  **project-scoped** `SetKind` and selects it.
- Kind is never required.

## Acceptance criteria

- [ ] A creator can set and clear a kind; unclassified is a valid saved state.
- [ ] Typing a novel kind creates a project-scoped `SetKind` and selects it.
- [ ] Selecting an existing kind does not create a duplicate row.
- [ ] No validation rejects a kind string for not being in a list.
- [ ] Banner and description render on the set page.
- [ ] `mix ck` clean.

---

## #121 8. Set deletion with blast-radius confirmation

- state: todo
- parent: #113

# 8. Set deletion with blast-radius confirmation

**Phase 2 (set workspace). Depends on #6.**

## Context

Deletion **cascades all the way down** — a set takes its child sets, and every
card, alt and aspect in all of them. That was a deliberate choice over nullify,
which means the *entire* safety burden sits on the confirmation dialog. It has a
real job: state the blast radius, not ask a generic "are you sure?".

## Work

- Destroy action cascading child sets, cards, alts and aspects.
- Count **before** opening the dialog: number of child sets, total cards + alts
  across all of them, and whether any of them is **published**.
- Use `confirm_button` / `confirm_dialog` from `SanctumWeb.CoreComponents`.

## Watch out

- **Never `data-confirm`.** It calls `window.confirm`, which WebKit suppresses in
  iOS standalone / Add-to-Home-Screen mode — the dialog never shows, the call
  returns false, LiveView cancels silently, and the button just looks dead.
- The published-descendant flag matters most: losing a public URL is the part
  people regret, and it is invisible from the parent set.
- Images are content-addressed and shared across cards, projects and users —
  **never** delete the Tigris objects.

## Acceptance criteria

- [ ] The dialog names the child-set count, the total card + alt count, and flags
      any published descendant.
- [ ] Deleting removes child sets and all contents.
- [ ] Official cards targeted by deleted `CardAlt` rows are untouched.
- [ ] No Tigris objects are deleted.
- [ ] Works in iOS standalone / PWA mode.
- [ ] Cancelling deletes nothing.
- [ ] `mix ck` clean.

---

## #122 9. Move cards between sets + parent/child nesting

- state: todo
- parent: #113

# 9. Move cards between sets + parent/child nesting

**Phase 2 (set workspace). Depends on #6.**

## Context

Creators need to reorganize after uploading, and to express the one structural
relationship the model supports: a hero set carrying its nemesis set, or a
campaign carrying its scenarios. Cross-*project* moves are deliberately deferred.

## Work

- Move one or many cards to another set **within the same project**.
- Set and clear a set's `parent_set_id`.
- Render child sets on the parent's page.

## Open question to settle here

**Nesting depth.** Recommendation is a **one-level cap**: both real cases are one
deep, and a cap keeps the delete blast radius (#8) a simple count rather than a
recursive walk over a tree whose consequences nobody can see from the top. It
constrains structure depth, not what content can exist, and is trivially relaxed
later. Confirm before building.

## Acceptance criteria

- [ ] Moving a card updates only `homebrew_set_id`.
- [ ] Moving to a set in another project is not offered and is rejected server-
      side if attempted.
- [ ] A parent link can be set and cleared.
- [ ] Child sets render on the parent set's page.
- [ ] If depth is capped, nesting deeper is prevented with a clear message rather
      than a crash.
- [ ] `mix ck` clean.

---

## #123 10. Creator-scoped slugs and public routing

- state: todo
- parent: #113

# 10. Creator-scoped slugs and public routing

**Phase 3 (publish & directory). Depends on #5.**

## Context

Published sets need shareable URLs. Slugs are **scoped to the creator**, giving
`/custom/@creator/:slug`, because collisions in a homebrew community are
guaranteed — there will be many Daredevils — and globally unique slugs would make
the second publisher take `daredevil-2` and turn being first into a land grab.
Creator scoping makes collisions structurally impossible and puts attribution in
the URL, which matters where "whose version is this?" is the constant question.

## Work

- `slug` on `HomebrewSet`, with a unique identity on `(creator_id, slug)`.
- Generate from the name; disambiguate only within the creator.
- Public routes `/custom/@:username/:slug`.
- Depends on a claimed username (gated in #11).

## Open question to settle here

**Username changes break every published set URL.** Either usernames are
claim-once, or renaming must leave stored redirects behind. Worth settling before
the first public link goes out, not after.

## Acceptance criteria

- [ ] Two different creators can both own the slug `daredevil`.
- [ ] The same creator publishing two sets named "Daredevil" gets a disambiguated
      second slug.
- [ ] A slug is stable across set renames unless explicitly regenerated.
- [ ] The route resolves a creator + slug pair to exactly one set.
- [ ] Username-change behavior is decided and implemented (claim-once or
      redirects), not left implicit.
- [ ] `mix ck` clean.

---

## #124 11. Publish flow: visibility ladder, attestation, username gate

- state: todo
- parent: #113

# 11. Publish flow: visibility ladder, attestation, username gate

**Phase 3 (publish & directory). Depends on #10.**

## Context

Publishing is the deliberate outward act that turns private work into public
content. It happens **per set**, from the set page the creator is already on — so
someone can publish eight heroes and keep four in draft, which was impossible
when visibility sat on the project.

## Work

- Drive `:private → :unlisted → :published` through the set's `set_visibility`
  action (kept separate from general editing for exactly this).
- First publish requires a **claimed username** for attribution.
- First publish requires a **publish attestation** checkbox, stored on the set
  with a timestamp.
- Provide the path back to private (unpublish).

## Why attestation twice

These are two different claims, and the second is the one that carries weight in
a takedown:

- **At project creation:** "I'm allowed to store this." Covers private hosting.
- **At first publish, per set:** "I'm allowed to distribute this, publicly, under
  my name." Dated, scoped to specific content, tied to a username.

## Acceptance criteria

- [ ] Publishing without a claimed username is blocked, with copy that says why
      and links to claim one.
- [ ] The publish attestation is recorded on the set with a timestamp.
- [ ] Publishing makes the set's contents visible to a nil actor (ties to the #4
      policies).
- [ ] Unpublishing hides them again.
- [ ] The ladder is walked via `set_visibility`, never via the general `update`.
- [ ] `mix ck` clean.

---

## #125 12. Unlisted share links

- state: todo
- parent: #113

# 12. Unlisted share links

**Phase 3 (publish & directory). Depends on #11.**

## Context

`:unlisted` is the middle rung of the visibility ladder: reachable by anyone with
the link, but absent from the directory and from card-level search. It is how a
creator shares work-in-progress to Discord for feedback before publishing.

## Work

- A **dedicated read action** keyed on creator + slug that resolves unlisted
  sets, so the global read filter never has to loosen to accommodate them.
- Share-link UI on the set page.

## Watch out

Do **not** widen the default read filter to include `:unlisted`. The global
filter stays private-by-construction; unlisted access is an explicit, separate
read path. Getting this wrong leaks unlisted sets into browse and search.

## Acceptance criteria

- [ ] An unlisted set is reachable by direct link, including by an anonymous
      visitor.
- [ ] An unlisted set does **not** appear in the directory.
- [ ] An unlisted set's cards do **not** appear in card-level search.
- [ ] The default read action still excludes unlisted sets — asserted by test.
- [ ] Leak test covers unlisted-not-in-browse.
- [ ] `mix ck` clean.

---

## #126 13. Public set directory + set detail page

- state: todo
- parent: #113

# 13. Public set directory + set detail page

**Phase 3 (publish & directory). Depends on #11. The payoff task.**

## Context

This is the answer to the discoverability half of the problem: today custom
content is scattered across per-creator Google Drives, Discord CDN links and BGG
threads, with no search and curation locked inside a 6.2k-member Discord.

The directory is a **flat filterable grid** — the `/decks` shape, not
`/browse`'s wave hierarchy. Homebrew has no release cadence, so there is no
spine to hang a hierarchy on.

## Work

- `/custom` — grid of published sets. Facets: kind, creator, maturity, tags,
  recency. Tile: banner, name, creator, kind badge, card count.
- `/custom/@creator/:slug` — description, creator attribution, contents grouped
  by child set then by card, "unofficial fan content" labeling, report button
  (wired in #14).
- Comic-dossier design, consistent with the rest of the app.
- Reuse `/browse/:pack`'s grouped-contents rendering as components where it fits.

## Acceptance criteria

- [ ] Only `:published` sets appear — never private, never unlisted.
- [ ] Every facet filters correctly and combines with the others.
- [ ] Anonymous visitors can browse and open set pages.
- [ ] A set with no kind appears under "Other" rather than being hidden.
- [ ] **The degenerate case renders acceptably**: one unnamed set with 200 loose,
      unenriched images still displays and is still shareable.
- [ ] "Unofficial fan content" labeling is present on public surfaces.
- [ ] `mix ck` clean.

---

## #127 14. Report/takedown flow + lift the admin gate

- state: todo
- parent: #113

# 14. Report/takedown flow + lift the admin gate

**Phase 3 (publish & directory). Depends on #13. Closes the phase.**

## Context

The homebrew feature has been **temporarily admin-gated** while it incubates: the
routes sit in the `:admin_routes` live session and the sidebar link hides from
non-admins. That was deliberately router-level only, so reopening is a route move
with **zero policy churn**.

End of phase 3 is the right moment: the feature is coherent for both audiences —
a creator can organize and publish, a visitor can find what was published.
Everything after this is depth, not completeness. (Note this differs from the old
roadmap, which tied the gate to the player-card play slice; play integration is
out of scope here.)

Opening uploads to the public also makes a working takedown path a prerequisite,
not a nicety.

## Work

- Report button on public set pages; reports create records in an admin queue.
- Admin unpublish action (distinct from delete).
- Move the homebrew routes from `:admin_routes` to `:authenticated_routes`.
- Unhide the sidebar link; restore non-admin LiveView test actors.
- `/custom` public routes are unauthenticated.

## Acceptance criteria

- [ ] A non-admin signed-in user can create projects and sets, upload, and
      publish.
- [ ] Anonymous visitors can browse `/custom`.
- [ ] A report creates a record an admin can see and action.
- [ ] An admin can unpublish a set without deleting it.
- [ ] **No policy changes were required to lift the gate** — the diff is a route
      move plus the sidebar and test-actor changes.
- [ ] IP posture intact: no monetization anywhere on these surfaces, © FFG /
      © MARVEL notices present, non-affiliation stated.
- [ ] `mix ck` clean.

---

## #128 15. origin: search field in the card pool

- state: todo
- parent: #113

# 15. origin: search field in the card pool

**Phase 4 (card-level discovery). Depends on #4.**

## Context

Discovery has two halves. Sets answer "what did people make"; **cards** answer "I
need a custom Spider-Man ally". Publishing granularity is not browsing
granularity — you publish a set, but people search individual cards.

This makes published customs *findable* in the existing pool. The read policies
(#4) already control what's *visible*; this is about surfacing it.

## Work

- Add `origin:` / `official:` to the card search registry (a registry-only
  change).
- Published custom cards appear in `/cards`; a creator's own private customs are
  findable by them.
- The alt-art target picker already filters `card.origin == :official`
  server-side and can switch to the registry field.
- Document the field in `/search-help`.

## Acceptance criteria

- [ ] `origin:custom` and `origin:official` filter correctly.
- [ ] Another user's unpublished customs never appear, for any query.
- [ ] A creator's own private customs appear for them.
- [ ] The field is documented on `/search-help`.
- [ ] `mix ck` clean.

---

## #129 16. Alt-art gallery

- state: todo
- parent: #113

# 16. Alt-art gallery

**Phase 4 (card-level discovery). Depends on #13.**

## Context

Alt art is browsed **card by card, never as collections** — nobody wants "a
collection of alt art", they want the images. So it needs a flat gallery, not a
directory entry.

It gets its own surface rather than folding into `/cards` for two concrete
reasons: its facets are genuinely different (who is depicted, who drew it, what
card it replaces — not cost, aspect or traits), and `CardAlt` rows are not
`CardSide` rows, so folding it in would mean a union query.

## Work

- New surface querying `CardAlt` where `origin == :custom` and the owning set is
  published.
- **Default grouping by depicted character** — a flat wall of thousands of images
  is useless. The link already exists: `CardAlt.card_id → Card.set → Hero.set`
  (`Sanctum.Heroes.Hero` has a `set` attribute and joins `cards` on it).
- Filters: artist, creator, target card.
- Link out to the official card's detail page and to the owning set.

## Note on the third path

The highest-intent route to alt art is neither this gallery nor the directory —
it is arriving from the official card you already care about. That strip exists
on `/cards/:id` today and is display-only until #17.

## Acceptance criteria

- [ ] Groups by depicted character by default.
- [ ] Artist, creator and target-card filters each work.
- [ ] Only alts in published sets appear.
- [ ] Links back to the official card detail and to the owning set.
- [ ] Anonymous browsing works.
- [ ] `mix ck` clean.

---

## #130 17. UserArtPreference: apply chosen art at render

- state: todo
- parent: #113

# 17. UserArtPreference: apply chosen art at render

**Phase 4 (card-level discovery). Depends on #16.**

## Context

Custom alt art has been display-only since it shipped — you can see that it
exists on a card's detail page, but you cannot *use* it. This is the task that
makes alt art actually worth uploading, and it closes the highest-intent
discovery path (arriving from the official card you already care about).

## Work

- `UserArtPreference`: user × card side → `card_alt`.
- Applied at render via a **preloaded map**, following the existing
  hero-gradient pattern rather than per-card queries.
- The art picker offers three sources: the canonical image, official reprint art
  (already in `CardAlt.image_url`), and published custom alts.

## Acceptance criteria

- [ ] Setting a preference changes that card's art everywhere it renders **for
      that user**.
- [ ] Other users are unaffected.
- [ ] A preference pointing at an alt whose set is later unpublished degrades
      gracefully to the canonical image — never errors, never leaks.
- [ ] The picker shows all three sources.
- [ ] No N+1: art preferences are preloaded, not queried per card.
- [ ] `mix ck` clean.

---

## #131 18. SetRelease + review workflow

- state: todo
- parent: #113

# 18. SetRelease + review workflow

**Phase 5. Deliberately last — designed for, not urgent.**

## Context

The custom-content community runs a strict review and versioning process that
keeps quality and parity with the game high. Supporting it is the long-term
goal, and the set-as-published-unit decision is what makes it tractable: reviews,
versions and approvals attach to a *set*, matching the community's own unit.
Under the old project-as-unit model, patching one hero would have re-versioned
eleven bystanders.

## Work

- `SetRelease` per set: `version`, `changelog`, jsonb card-data snapshot.
- **Live-latest stays**: card rows always reflect current state; releases exist
  for history and diffing, not frozen per-release row copies.
- **Draft isolation ships with review, not before** — these are coupled more
  tightly than the old roadmap implied. A review gate must approve a *frozen*
  state, so the moment the directory is reviewed, live post-publish editing has
  to end. Until then, edits going live immediately is correct.
- Review, comments and approval attach to the set. Surface the Homebrew
  Discord's "Community Approved" (Cycles) status as a badge.
- Deck drift: nullable `built_against_release_id` plus a "this set has updated
  since you built this deck" notice — **never** forced migration.

## Acceptance criteria

- [ ] Publishing creates a `SetRelease` with a version and a snapshot.
- [ ] The changelog is visible on the public set page.
- [ ] Post-publish edits accumulate privately and go live only on the next
      publish or re-review.
- [ ] Decks referencing a drifted set show a notice; nothing is force-migrated.
- [ ] A reviewed set displays its approval status.
- [ ] `mix ck` clean.

---

## #132 Investigate how we can generate "how-to" or demo videos

- state: doing

(empty body)

---

## #133 Google Drive import for homebrew content

- state: todo

# Google Drive import for homebrew content

**Related: #113 (custom content sets/publishing/discovery). Independent of it —
this feeds the upload pipeline that already exists.**

## Why this matters

The community ships homebrew as **Google Drive folders**. That is the single
most-cited fact about how custom content is distributed today, and it is the
premise the whole custom-content effort started from: content lives in
per-creator Drives, Discord CDN links, BGG threads and TTS mods — fragile
hosting, no search, curation locked inside a ~6.2k-member Discord.

"Import from a Drive link" is therefore the acquisition path that meets creators
where they actually are, instead of asking them to re-upload a back catalogue by
hand.

## What's already built

Everything downstream. The `Sanctum.HomebrewImages` pipeline, the image
Processor, content-addressed `homebrew/<sha256>` keys in the Tigris
`sanctum-cards` bucket, and the enrichment UX all exist. **The only new work is
acquisition** — getting bytes from Drive into that pipeline.

## Approaches, cheapest → most powerful

The entire cost is dominated by **Google OAuth scope + app verification**, not
code. Sanctum's current Google sign-in requests identity-only scopes
(`openid email profile`) and does not persist the access token, so any Drive
access is net-new consent + token plumbing.

### A. Public-share-link fetch — RECOMMENDED FIRST

Most homebrew Drives are "anyone with the link". The server enumerates and
downloads with an API key (or unauthenticated for direct file links):
`files.list` on the folder ID + `files.get?alt=media`, streamed into the existing
Processor.

- New code: a `Sanctum.GoogleDrive` module (list + download), a URL/folder-ID
  parser, one LiveView "import from Drive link" field.
- **No verification, no CSP change, no token storage.** Pure server-side `Req`
  calls; needs only a `GOOGLE_API_KEY` env var, or nothing for public direct
  links.
- Watch out: Drive's virus-scan interstitial on large files needs the `confirm=`
  token dance.
- Limitation: public folders only, never a user's private Drive.
- **Estimated ~1–2 days.**

### B. `drive.file` scope + Google Picker — private-Drive integration

User connects Drive; the Picker UI lets them select specific files/folders; the
app gets access only to what was picked (the scope Google intends for this).

Beyond A this needs: OAuth tokens persisted with `offline` access and refresh-
token storage (stock `UserIdentity` doesn't keep them), an incremental-
authorization consent flow *separate from sign-in*, and the Picker JS — which
loads `apis.google.com`, a **CSP change deliberately avoided so far** (single
dark theme, self-hosted everything).

Verification: `drive.file` is a *sensitive* scope → consent-screen verification
(homepage, privacy policy, domain ownership, brand review), weeks of
back-and-forth, **but no third-party audit**.

**Testing-mode escape hatch:** Google allows sensitive/restricted scopes for up
to 100 allowlisted test users with *no* verification. While homebrew is still
admin-gated, B could ship by adding creators as test users; verification only
becomes mandatory when the feature opens broadly.

### C. `drive.readonly` (full-Drive read) — AVOID

*Restricted* scope → triggers Google's annual CASA third-party security
assessment (recurring money + overhead). Not justifiable for this app.

## Recommendation

Ship **A** first — it matches how content is actually shared, reuses the whole
pipeline, and sidesteps consent, tokens, CSP and verification entirely. Reach
for B (with testing-mode allowlisting, not full verification) only if importing
from *private* Drives turns out to be required.

## Interaction with #113

Under the set-first model, an import needs a **destination set**. Import should
either target an existing set or create one named after the Drive folder — which
is a natural mapping, since creators already use folder names as set names.

## Acceptance criteria

- [ ] A creator can paste a public Drive folder or file link and import the
      images into a chosen (or newly created) set.
- [ ] Images flow through the existing Processor and land as content-addressed
      `homebrew/<sha256>` objects — no bypass of the normal pipeline.
- [ ] Each imported image becomes a custom `Card` in the destination set, exactly
      as a manual upload would.
- [ ] The virus-scan interstitial on large files is handled (`confirm=` token),
      not silently truncated.
- [ ] A non-public or invalid link fails with a message that says what went wrong
      and how to fix it.
- [ ] No CSP change, no persisted OAuth tokens, no new consent scope (approach A).
- [ ] Import is attributable — the attestation still applies to imported content.
- [ ] `mix ck` clean.

---

## #134 Friendly referential integrity for cards used in decks

- state: todo

# Friendly referential integrity for cards used in decks

**Related: #113, and specifically its subtask #121 (set deletion). Currently
dormant — see "when this wakes up".**

## The problem

`DeckCard` and `GameCard` hold card FKs with **no cascade**. Deleting a custom
card that a deck references raises a **raw Postgres foreign-key error** — an
unhandled 500, not a useful message.

There are already `TODO(play-slice)` markers sitting at two of the call sites:
`Sanctum.Games.Changes.PairCustomCard` and
`Sanctum.Games.Changes.DeclareAltArt`. Pairing two custom cards destroys the
donor row, and declaring a custom card as alt art destroys the card row — both
can hit this.

## When this wakes up

It is **dormant today**: custom cards don't reach the deckbuilder yet, so no
deck can reference one, and the paths above can't actually fail in production.

It wakes up the moment custom player cards become deck-selectable.

**Set deletion (#121) then becomes the third and worst caller.** Deleting a set
cascades across every card in it, so the failure happens partway through a
multi-row cascade rather than on a single card — a partial delete with an opaque
error, instead of one card refusing to go.

## Work

- Convert the raw FK error into a proper Ash validation — "this card is used in a
  deck" — with the deck named, so the user can act on it.
- Cover all callers: `PairCustomCard`, `DeclareAltArt`, single-card destroy, and
  **set destroy**.
- Decide the policy for each: refuse, or cascade and notify. Refusing is right
  for single-card operations; set deletion already cascades by design, so it
  needs the count surfaced in the confirmation (#121) rather than a refusal.
- Remove the `TODO(play-slice)` markers once handled.

## Sequencing

Not worth building before custom cards are deck-selectable — there is nothing to
reference. But it must land **with or before** that change, not after, because
the first symptom is a 500 on someone's real content.

## Acceptance criteria

- [ ] Destroying a custom card referenced by a deck produces a clear validation
      error naming the deck, never a raw FK error.
- [ ] `PairCustomCard` and `DeclareAltArt` both surface the same friendly error.
- [ ] Set deletion reports the referencing decks up front rather than failing
      partway through the cascade.
- [ ] The two `TODO(play-slice)` markers are gone.
- [ ] Regression test per call site.
- [ ] `mix ck` clean.

---

## #135 Custom aspects, phase 2 (creator-defined aspects)

- state: todo

# Custom aspects, phase 2 (creator-defined aspects)

**Related: #113. Phase 1 is shipped; this is the additive half.**

## Context

`CardAspect` / `DeckAspect` used to be hard-coded enums. That enum was **the one
place where non-conformance actually lost data** — the vision extractor forced
every `aspect` into the five official values, so a custom aspect on a homebrew
card was silently destroyed on extraction.

**Phase 1 shipped** (commits `217bcd21`, `68b26590`): `Sanctum.Games.Aspect` is a
data-driven lookup resource keyed on a stable string `key`, with `label`,
`color`, `sort_order`, `origin` and a nullable `homebrew_project_id`.
`CardSide.aspect` is a string column plus a `belongs_to :aspect_def`;
`deck.aspects` is `{:array, :string}`. That was a deliberate zero-behaviour-change
refactor covering official aspects only.

**Phase 2 is the creator-facing half, and it is not built.** The resource can
already hold a custom aspect; nothing lets a creator make one.

Full plan and touchpoint inventory: vault
`01 - Projects/Personal/Sanctum/plans/2026-07-23-aspect-as-resource.md`.

## Work

- Creator UI to define an aspect: `key`, `label`, display `color`.
- Custom aspects are **project-scoped** and inherit their set's visibility (see
  #113 — `Aspect` gains a `homebrew_set_id` there, which is what makes an aspect
  publishable at all).
- Rendering: custom aspect colors render via **inline style**; official aspects
  keep their compile-time `bg-aspect-*` Tailwind utilities. Tailwind cannot
  generate classes for colors that don't exist at build time — do not try.
- Vision extractor reconciliation: a `custom_aspect` path so extraction stops
  coercing to the five official values and can propose a new aspect instead.
- Custom aspects appear in the deckbuilder's aspect selection for decks that use
  the owning set (advisory legality, consistent with existing philosophy).

## Why it's worth doing

This unlocks genuine fifth-aspect projects — the community's Determination
aspect being the flagship example — which are currently unrepresentable rather
than merely awkward.

## Acceptance criteria

- [ ] A creator can define an aspect with a key, label and color inside a set.
- [ ] The custom aspect renders with its color everywhere aspects render, via
      inline style rather than a generated Tailwind class.
- [ ] Official aspects still render through their compile-time utilities —
      unchanged.
- [ ] A custom aspect is only visible where its set is visible (private stays
      private).
- [ ] The vision extractor can propose a custom aspect instead of coercing to one
      of the five official values.
- [ ] Two projects can define aspects with the same key without collision.
- [ ] `mix ck` clean.

---

## #136 Bulk vision enrichment: extract-all per set

- state: todo

# Bulk vision enrichment: extract-all per set

**Related: #113. Also pairs naturally with Google Drive import.**

## Context

"Fill from image" (`Sanctum.CardVision`) exists and works, but it is **per-card
only** — a button press per card. For a creator importing a back catalogue, that
is the dominant cost of getting content into a usable state.

The benchmark that settled the model choice also settled the economics. From
`mix sanctum.vision_eval` (PR #322), 12-card seeded sample, strict scoring:

| Model | Accuracy | ¢/card | Note |
|---|---|---|---|
| Claude Opus 5 | 93% | 3.3¢ | best; not worth 2.5× Sonnet for human-reviewed fills |
| **Claude Sonnet 5** | **90%** | **1.2¢** | **current default** |
| Gemma 4 31B (local) | 78% | ~0 | free on an M-series Mac, ~29s/card |
| Qwen3.5-122B (open) | 75% | 0.26¢ | best hosted-cheap tier |

**The conclusion that drives this task:** a 300-card project costs ~$4–5 to fully
auto-enrich on Sonnet 5 — *"cheap enough to offer 'extract all' per project
rather than per-card button presses."* That was recorded as a finding and never
built.

## Work

- An "extract all" action scoped to a **set**, queued through Oban so it survives
  a page close and reports progress.
- Progress reporting over PubSub, in the style of `Sanctum.CardSync.Server`.
- Results land as normal enrichment — always reviewable and editable, never
  authoritative. The standing rule holds: metadata is never required, and the
  image is the card.
- Respect the BYOK setup already shipped (`b36bc91a`) — bulk extraction runs on
  the creator's own key, which also makes the cost question theirs.

## Deferred within this task

The **two-tier escalation flow** — Qwen3.5-122B or local Gemma first, escalating
to Sonnet 5 only on validation failure — cuts cost ~5–10× at similar quality.
Not worth building until bulk volume is real; revisit if Drive import starts
pulling in whole back catalogues.

## Useful findings to build against

- **The stat block (ATK/HP/SCH) is the discriminator field.** Everything
  Sonnet-class and above reads it perfectly; everything below misreads or
  hallucinates it. Don't pay frontier prices for text-only card types.
- **Anthropic tokenizes card scans at ~4.8k input tokens** (~2–3× other
  providers' image tokenizers) — real cost is roughly double naive estimates.
- **Text transcription scores low everywhere (≤36%)** but that's a threshold
  artifact from `<b>`/icon-token formatting conventions, not misreads. Fine for
  human-reviewed fills.
- Tigris serves JPEG bytes under `.png` names — the data-URL media type must be
  sniffed from magic bytes or Anthropic 400s on mismatch. Already fixed; don't
  regress it.

## Acceptance criteria

- [ ] A creator can trigger extraction across a whole set from the set page.
- [ ] The job runs in Oban and survives the creator closing the page.
- [ ] Progress is visible while it runs; failures are per-card, not fatal to the
      batch.
- [ ] Every extracted field remains editable afterwards; nothing is locked.
- [ ] Extraction uses the creator's own API key (BYOK), with the estimated cost
      shown before starting.
- [ ] Cards that already have metadata are not silently overwritten without
      consent.
- [ ] `mix ck` clean.

---

## #137 Custom content: deferred ecosystem + play integration

- state: someday

# Custom content: deferred ecosystem + play integration

**Holding task.** Everything the custom-content roadmap carried that is real
future work but deliberately not scheduled. Captured here so it survives the
roadmap file's deletion; split any item out into its own task when it gets
picked up.

---

# Play integration (out of scope while the table isn't usable)

## Player-card slice

- Custom player cards appear in the owner's deckbuilder (advisory legality;
  degrade gracefully when cost/aspect are absent).
- Decks containing custom cards build/save/render normally (`deck_source`
  already distinguishes native).
- *Referential integrity is now its own task — see "Friendly referential
  integrity for cards used in decks".*

## Scenario slice

- **Set grouping for game setup** plus **encounter `quantity`**. Note the
  grouping half is now solved by `HomebrewSet`; what's missing is the setup
  hint — which zone a set's cards start in — plus multiplicity.
- Official encounter multiplicity is one `Card` row per copy; `deck_limit` is
  MarvelCDB's product quantity, not a play quantity. A new attribute is needed,
  plus duplication in `create_game_encounter_deck`.
- Custom scenario playable at the owner's table: villain stages, schemes,
  encounter deck built from quantities. Missing stats mean players set tokens
  manually — player-enforced rules, by design.
- **Game-setup reads are actor-less today** and therefore correctly exclude
  customs. The game owner must be threaded through as actor when this lands.

---

# Ecosystem

## Tabletop Simulator deck export

Generate an importable TTS Saved Object (`.json`) from a set's own cards, so
people can play homebrew on TTS — including on community tables like Hitch's
Table (Workshop `2514286571`). Shares a sprite-sheet packing engine with the
print-sheet export; only the output wrapper differs.

**Approach: standalone deck object, not a mod.** Emit a `DeckCustom` object the
user spawns via TTS's local Saved Objects folder. TTS lets any object be dropped
onto any table, so custom cards ride on top of Hitch's generic scripted
infrastructure (villain mat, built-in HP counter, threat/HP on seat count).

- **Not** a Workshop mod: per-user Steam publishing can't be automated, and a
  full self-contained table is the DMCA-risk shape — full-game reproductions are
  what got MC TTS mods taken down.
- **Not** integration with Hitch's importer: his Lua importer is hardcoded to
  MarvelCDB's API and `^[0-9]{5}` code schema and rejects unknown decks. Making
  it load Sanctum would need his cooperation or a fragile MarvelCDB-API
  impersonation, and `custom-<uuid>` codes collide with his expectations.

**Format (TTS save spec):** a deck is JSON with `DeckIDs` + `CustomDeck`, a dict
of sprite **sheets** (`FaceURL`, `BackURL`, `NumWidth`, `NumHeight`,
`UniqueBack`, `BackIsHidden`). Cards pack into grids, **max 10×7 = 70 per
sheet**. Card ID = `sheet_number * 100 + grid_index` (index 0-based,
left→right, top→bottom): hundreds place selects the sheet, remainder the cell.
Prior art proving the format is routine: MCdeck and the community Card Maker
both already export TTS saves from custom cards.

**Work item — the sprite-sheet packer:** pack `CardSide.image_url` images into
grid sheets, upload sheets to the `sanctum-cards` Tigris bucket (reuse the
homebrew Processor), emit the JSON with correct IDs. Double-sided cards
(`is_multi_sided` / `primary_side`) map to `UniqueBack` / back-sheet fields — the
model already has the data.

**Scope + IP:** export a set's *own* cards only — never mix official scans into
the generated object. A custom-content-only deck is exactly what Asmodee's
community-use policy blesses.

Research: vault `[[2026-07-22-tts-mod-export-feasibility]]`.

## Other ecosystem items

- **Card Maker JSON/ZIP importer** (champions-card-maker.pages.dev) — structured
  import for creators using the community's flagship tool. Deferred originally
  because the back catalogue is images, not JSON.
- **Stable export/read API** so other tools (Digital Edition, Cardtable,
  DragnCards) can consume Sanctum-hosted content — the "become infrastructure"
  play. Consider publishing the format (marvelsdb schema + a set envelope).
- **Print-sheet / MPC-ready export** from a set. Shares the sprite-sheet packer
  with TTS export.
- **Native card editor** — only if demand appears; arkham.build never built one.
- **Community enrichment** — non-creators proposing metadata fixes.

---

# Standing constraint these items exist under

**Never host bulk-downloadable packs of official card scans**, and homebrew
upload must not become a proxy channel for official cards. This constraint is
aimed squarely at print-sheet and TTS export, which are the two features capable
of violating it — both are scoped to a set's own cards for exactly that reason.

Related: **consider DMCA agent registration** if uploads open up broadly (noted
against the report/takedown flow).

---

# Strategic question, not a work item

**Ambition: personal-plus vs. THE community hub.** The hub path means courting
the Homebrew Discord and Hall of Heroes early — social buy-in mattered as much
as the technology for both arkham.build and ALeP. This decision reshapes
priority rather than adding a task.

Also unresolved: **non-Marvel conversions** (DC, TMNT, He-Man…) — a big popular
slice that multiplies third-party IP surface. arkham.build's answer was to ban
them from the public directory while allowing private import, which maps onto
this model cleanly as a visibility restriction rather than an upload one.

---

## #454 Move Jessica Jones and Luke Cage packs to wave 11

- state: done

The JJ and LC packs are showing up under "OTHER" in the packs page right now. They belong under "Wave 11" with the FNE box.

**Implementation log (2026-09-30):** Added `"jj" => {:hero_pack, 11}` and `"luke_cage" => {:hero_pack, 11}` to the Wave 11 (Fear No Evil) section of `@packs` in `lib/sanctum/catalog/curated.ex`. The two packs had no curated entry, so `product_type`/`wave_id` were null and they showed up under OTHER. I ran `Curated.apply!()` against the local dev DB and confirmed both packs now have hero_pack / Wave 11. The other environments pick it up on the next card sync or seed run (apply! is idempotent and runs during sync). Committed as `rxp` on the new independent GitButler branch `wave-11-jj-luke-cage`; it is not pushed.

**Review (2026-09-30): PASSED.** The diff adds 2 lines to `@packs` in `lib/sanctum/catalog/curated.ex` (`jj`, `luke_cage` → `{:hero_pack, 11}`). They are in the Wave 11 / Fear No Evil section and follow the existing pattern. In the dev DB, `jj` and `luke_cage` are both hero_pack / Wave 11, and no pack still has a null `product_type`, so nothing else would land under OTHER. The file passes the format check. `mix test` ran 989 tests with 1 failure: `HomebrewLive.ShowTest` "Upload button opens the type chooser (Alt art)". That test has nothing to do with this change and comes from in-flight homebrew work in the shared workspace.

**PR:** https://github.com/jwstover/sanctum/pull/412

---

## #455 Admin allow editing card image from public card show page

- state: review

As an admin, I would like to be able to easily upload an image for a card from the public card show page. 

I think that there should be a small icon in the bottom right of the card image display that I can click to upload a new image for the card.

## Plan

**Goal.** Let an admin replace a card face's image straight from the public card page (`/cards/:id`, `CardLive.Detail`): a small upload icon in the bottom-right corner of each face's art. Click it, pick a file, and it uploads; no form, no Save step. It reuses the bucket-overwrite pipeline that already exists on `/admin/cards/:id` (`CardLive.Show`), moved into a shared module first.

**Done when.**
- An admin on `/cards/:id` sees an upload icon at the bottom-right of every face's art. Picking a PNG/JPG/TIFF uploads it automatically, shows a spinner while it runs, swaps in the new image (cache-busted) and flashes "Image replaced."
- Anonymous visitors and non-admin users get no icon, no file input and no upload config. A forged event or upload from them does nothing.
- The admin Show page's "Replace image" flow still works, now running on the shared helpers. `mix ck` passes, including `ex_dna`, which fails on any duplicated code.

**Files.**
- `lib/sanctum/card_images.ex`: gets the pure pipeline moved out of Show: `replacement_key(image_url, code)` (`key_from_url(url) || "cards/#{code}.png"`), `store_replacement(path, key)` (read the file, `Processor.normalize/2` to the key's extension, then `put_object` with the content type taken from the key; returns `:ok | {:error, _}`), and `replacement_url(image_url, key)`. Show's private `target_ext` and `content_type_for` move here.
- `lib/sanctum_web/live/card_image_upload.ex` (new, `SanctumWeb.CardImageUpload`): `upload_opts/0` (accept `~w(.png .jpg .jpeg .tif .tiff)`, `max_entries: 1`, `max_file_size: 50_000_000`), `error_message/1` (Show's `upload_error_to_string` clauses), `persist_image_url(side_id, url, actor)` (the Ash update), and `versioned_url/2`.
- `lib/sanctum_web/live/card_live/show.ex`: same UX. Repoint it at the two modules above and delete the moved private functions.
- `lib/sanctum_web/components/card_side_tile.ex`: add `slot :art_overlay`, rendered inside the `maybe_link` art frame right after `<.mc_card>`, and add `relative` to that frame's classes. Leave `side_view/2` unchanged.
- `lib/sanctum_web/live/card_live/detail.ex`: per-side upload configs, the overlay icon, a progress handler, and the admin guard.
- `test/sanctum_web/live/card_live/detail_test.exs`: new tests.

**Steps.**
1. Extract: add the `CardImages` functions and `SanctumWeb.CardImageUpload`, then rewrite Show's `replace_image`/`put_entry`/`apply_replacement` to call them. Run `mix test test/sanctum_web/live/card_live/show_test.exs`; it must pass unchanged.
2. Tile: add the `:art_overlay` slot. Pool, home and homebrew don't pass it, so nothing changes there.
3. Detail, configure uploads: in `handle_async(:load_card, {:ok, {:ok, data}}, ...)`, only when `admin?(socket)` (`current_user && current_user.admin`), reduce over `data.sides` calling `allow_upload(socket, "card_image_#{side.id}", CardImageUpload.upload_opts() ++ [auto_upload: true, progress: &handle_image_progress/3])`. String upload names are valid (`allow_upload` guards on `is_atom or is_binary`). Add `assign(:uploading_side, nil)` in mount.
4. Detail, markup: pass `<:art_overlay :if={admin}>` to each tile. It holds a `<form id={"image-upload-#{side.id}"} phx-change="validate_image">` containing a `<label>` with an `sr-only` `live_file_input` for `@uploads["card_image_#{side.id}"]`. Copy the profile avatar picker in `profile_live/index.ex:28-60`. The label is a small square button anchored `absolute bottom-2 right-2`: black background, `border-2 border-neutral`, `hero-arrow-up-tray` icon (`hero-arrow-path animate-spin` while `@uploading_side == side.id`), `title="Replace image"`. Keep it always visible because touch/PWA has no hover. Upload errors go out as a flash.
5. Detail, handlers: `validate_image` sets `uploading_side` and reports upload errors via `CardImageUpload.error_message/1`. In `handle_image_progress("card_image_" <> side_id, entry, socket)`, when `entry.done?` and the user is admin: `Ash.get!(CardSide, side_id, actor: user)`, `key = CardImages.replacement_key(side.image_url, side.code)`, then `consume_uploaded_entry` calling `store_replacement(path, key)`. On `:ok`, if `side.image_url` was nil, persist the new URL; then set that side's `image_url` in `@sides` to `versioned_url(url, System.unique_integer([:positive]))`, clear `uploading_side` and flash info. On error, flash "Could not save the image." Non-admins: consume or cancel the entry and do nothing.
6. Tests (step 7 below).

**Out of scope.** Redesigning Show's two-step UI, alternate printings / `CardAlt` images, homebrew images and Pool tiles. Don't widen `side_view/2`. The overlay nested inside a `navigate` link (Pool) is unsupported; Detail has no `navigate`. No migrations or resource changes: the existing CardSide update policy (admin-only) already covers `image_url`.

**Decisions.** One-click auto-upload, because the task asks for "click icon to upload" and the profile/homebrew pickers set the precedent. One upload config per side, because each config renders exactly one `live_file_input`. Gate on the server, not just in markup: `put_object` sits behind no Ash policy, so configs only exist for admins and the progress handler re-checks admin. The object key is derived from the freshly loaded record, because Detail's display map lacks `code` and `object_key`. The uploaded bytes overwrite the same bucket key, which keeps the URL stable so syncs skip it (same behavior as Show).

**Verify.** build `mix compile --warnings-as-errors`, test `mix test`, lint `mix ck`, which runs format, credo, ex_dna and sobelow (`put_entry`-style `File.read` on the LiveView temp path is an existing ignored Sobelow false positive). Baseline was all green at planning time: 990 tests, 0 failures, no clones. Tests to add in `detail_test.exs`: an admin (`Sanctum.AccountsFixtures.admin_user_fixture`) sees the `image-upload-<side id>` form and a file input on each face; a `user_fixture` user and an anonymous conn see neither. The S3 write can't run in tests (`put_object` uses `System.fetch_env!`), so check it by hand with playwright-cli on http://localhost:4150/cards/<id> as an admin.

**Ship.** GitButler workspace: yes. Merge target: `main`. Base it on: `main` (no applied branch touches these files). Branch: `card-detail-image-upload`. Forge: github (CLI: gh). PR title: `feat(cards): admin image upload from the public card page`. Stage only this branch's hunks (the workspace has unrelated uncommitted demos/router/AUTH_ROADMAP changes) and review the staged diff before committing. Push with `but push card-detail-image-upload`, never bare `but push`.

## PR
https://github.com/jwstover/sanctum/pull/415

## Implementation
- Extracted the replace-image pipeline into `Sanctum.CardImages` (`replacement_key/2`, `replacement_url/2`, `store_replacement/2`) and a new `SanctumWeb.CardImageUpload`. `CardLive.Show` now uses both.
- Added an `:art_overlay` slot to `card_side_tile`. `CardLive.Detail` gets per-side, admin-only auto-upload configs, a bottom-right icon, and a server-side admin re-check in the progress handler.
- Deviations: `validate_image` is a no-op. Upload errors are flashed and the entry cancelled in the progress handler, which also sets the spinner. I also added an `uploads_enabled?` assign to gate the markup.
- Not done: the real S3 write and a playwright check, since there are no S3 env vars in this session. Tests cover the admin, user and anonymous UI.

---

## #522 dump tasks to md for import

- state: doing (this task)

I have a separate tend instance on another machine where I do most of the work for this repo. Can you dump the existing tend tasks for sanctum to a markdown file that I could then import into that separate tend instance with another agent? 
