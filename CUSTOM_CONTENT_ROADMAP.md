# Custom Content Roadmap

Working checklist for hosting community custom (homebrew) content in Sanctum.
Research and decision context: Obsidian vault under
`01 - Projects/Personal/Sanctum/` (see
`research/2026-07-20-custom-content-landscape.md`).

The gap: there is no MarvelCDB-equivalent for homebrew. Content lives in
per-creator Google Drives, Discord CDN links, BGG threads, and TTS mods —
fragile hosting, no search, curation locked inside the ~6.2k-member Homebrew
Discord. The proven model is arkham.build's fan-content system (project
format + reviewed directory + unrestricted private import), and Sanctum's
rules-free table is the enabling condition: a custom card is just an image
plus optional data, never code.

## Decisions made

- **Image-first import.** A homebrew card is a PNG (the source of truth)
  plus optional, progressively-added metadata. Card Maker JSON import is
  deferred — the community's back catalog is images, not JSON.
- **Same catalog tables, not a parallel system.** Homebrew cards are
  `Card`/`CardSide` rows with an origin flag and a project FK, so the card
  browser, search, deckbuilder, and game table work downstream for free.
- **The project is the discovery unit** (a hero pack, a scenario, a
  campaign) — matches how the community shares ("Juri Krasko's Daredevil"),
  and card-level metadata may be sparse.
- **Two-tier curation**: private import is unrestricted; the public
  directory is reviewed. Caps moderation load and IP exposure.
- **Versioning is live-latest** (supersedes the earlier "immutable
  snapshots" wording). Card rows always reflect the latest published
  state; each publish creates a `ProjectRelease` (version, changelog,
  jsonb card-data snapshot for history/diffing). No frozen per-release row
  copies. Players are protected by `GameCard`'s snapshot-stats-at-setup
  plus immutable image objects; decks drift with an "updated since you
  built this" notice (`built_against_release_id`), never forced migration.
  Post-publish edits are live immediately during the private/unlisted
  phases; **draft isolation ships with the public directory** — review
  must approve a frozen state, so the blog-post edit model ends there.
- **Advisory-only legality applies** (existing deckbuilder philosophy) —
  perfect fit for homebrew heroes with unusual deckbuilding rules.
- **New-aspect support is deferred.** MVP custom player cards use the four
  official aspects (or basic/pool). Whole new aspects (e.g. the community's
  "Determination") require `CardAspect` to become data-driven — an `Aspect`
  lookup resource replacing the enum, touching `DeckAspect`, the builder's
  aspect chooser, search registry, and aspect theming. Deliberate later
  refactor; nothing in the MVP schema makes it harder.
- **Alt art reuses `CardAlt`.** Custom alternate art for official cards is
  stored as `CardAlt` rows with an `origin` (`:official | :custom`)
  discriminator plus creator/project FKs — the uploader picks the target
  card, so `card_id` + `side_identifier` make the link concrete, and the
  art picker gets official reprint art (already in `CardAlt.image_url`)
  and custom uploads from one table. Custom rows get synthetic codes
  outside MarvelCDB's numeric space. Premise: full catalog wipes are
  retired as a maintenance technique. Custom card *backs* have no target
  card and are out of scope for CardAlt (defer).
- **IP posture**: free-only (no monetization anywhere near hosted IP),
  "unofficial fan content" labeling, creator attestation on upload,
  © FFG / © MARVEL notices, working report/takedown flow. Asmodee's
  community-use policy explicitly blesses free fan cards/scenarios; the
  real risk vectors are money and Marvel art.

## 1. Data model & domain (`Sanctum.Homebrew`)

- [ ] `HomebrewProject` resource — `creator` (User FK), `name`, `slug`,
      `description` (markdown), `banner_url`, `content_types` (array enum:
      hero / villain_scenario / modular_set / campaign / aspect / other),
      `maturity` (:draft | :beta | :complete), `visibility`
      (:private | :unlisted | :published), tags.
- [ ] `Card.origin` enum (`:official | :custom`, default `:official`) +
      nullable `homebrew_project_id` FK. Backfill/`ash.codegen` migration.
- [ ] Custom card codes: UUID-based, outside the official
      `^[0-9]{5}[abcdef]?$` space (no collisions; `CardAlt` fallback
      resolution untouched).
- [ ] Relax `CardSide` requirements for `:custom` origin — required: image;
      nudged: `name` (pre-filled from filename), `ownership`, orientation/
      `type`; everything else optional and editable forever.
- [ ] Policies: `:private` projects and their cards readable/writable by
      creator only (`relates_to_actor_via` pattern from Collections);
      `:published` readable by all; card catalog reads must now exclude
      other users' private customs by construction.
- [ ] Scenario support: homebrew projects can mint a set grouping (villain
      stages, main schemes, encounter cards with per-card `quantity`) that
      `Scenario`/game setup can consume like an official set.
- [ ] Alt art: `CardAlt.origin` discriminator + `creator_id` /
      `homebrew_project_id` FKs + artist credit; synthetic unique codes for
      custom rows; policy split on origin (mutations: admin for official,
      creator for custom; reads: official always, custom
      published-or-own). Consider filtering `by_code`/`by_codes` to
      `:official` so deck import never resolves through a custom row.
- [ ] `UserArtPreference` (user × card side → card_alt) applied at render
      via a preloaded map (hero-gradient pattern); art picker offers
      canonical image + official reprint art + published custom alts.

## 2. Upload pipeline & enrichment UX

- [ ] LiveView batch upload (drag-drop PNG/JPG/WebP) → Tigris bucket
      (`sanctum-cards` under a `homebrew/` prefix or a sibling bucket).
      Size/type validation, content hashing for dedupe. Content-addressed
      keys, objects never overwritten — replacing art mints a new URL, so
      old games/snapshots keep rendering the original by construction.
- [ ] Project page shows uploaded images as a card grid immediately —
      every image is already a playable card.
- [ ] Enrichment form per card (never required): name, ownership bucket,
      type/orientation (landscape toggle for schemes), aspect, cost, stats,
      quantity (encounter copies, default 1), traits, text.
- [ ] Side pairing gesture — link two images as front/back of one card
      (identity A/B, main scheme A/B) → `is_multi_sided` + two `CardSide`s.
- [ ] Grouping within a project: hero deck / encounter set / modular set
      buckets so game setup knows what shuffles where.
- [ ] Upload attestation checkbox ("my work or shared with creator's
      permission") stored on the project.

## 3. Play integration (private-first MVP exit criteria)

- [ ] Custom player cards appear in the owner's deckbuilder (advisory
      legality; degrade gracefully when cost/aspect absent).
- [ ] Decks containing custom cards build/save/render normally
      (`deck_source` distinguishes native already).
- [ ] Custom scenario playable at the owner's table: villain stages,
      schemes, encounter deck built from quantities; missing stats mean
      players set tokens manually (player-enforced rules, by design).
- [ ] Card browser/search: `origin`/`official:` field in the search
      registry; own private customs visible only to self.

## 4. Publish & discovery

- [ ] Publish flow: `:private → :unlisted (share link) → :published`
      (directory). Each publish creates a `ProjectRelease` (version,
      changelog, jsonb card-data snapshot).
- [ ] Deck drift notice: nullable `built_against_release_id` on decks +
      "this project has updated since you built this deck" indicator.
- [ ] Draft isolation (lands WITH the directory, not before): post-publish
      edits accumulate privately and go live on the next publish/re-review
      — the review gate must approve a frozen state.
- [ ] Directory LiveView: project cards (banner, author, content types,
      maturity, tags), search + filters. Comic-dossier design.
- [ ] Directory gate: admin review to start; design for a future
      community-review path. Surface the Homebrew Discord's
      "Community Approved" (Cycles) status as a badge/tag.
- [ ] Attribution: creator username required before first publish
      (the profiles roadmap already anticipated this).
- [ ] Report/takedown flow: report button, admin queue, unpublish action.
      Consider DMCA agent registration if uploads open up broadly.
- [ ] "Unofficial fan content" labeling + non-affiliation and © notices on
      all homebrew surfaces.

## 5. Ecosystem (later)

- [ ] Card Maker JSON/ZIP importer (champions-card-maker.pages.dev) —
      structured import for creators using the community's flagship tool.
- [ ] Stable export/read API so other tools (Digital Edition, Cardtable,
      DragnCards) can consume Sanctum-hosted projects — the "become
      infrastructure" play; consider publishing the format (marvelsdb
      schema + project envelope).
- [ ] Print-sheet / MPC-ready export from a project.
- [ ] Native card editor (only if demand; arkham.build never built one).
- [ ] New-aspect support: `CardAspect` enum → `Aspect` lookup resource
      (official four seeded; homebrew aspects project-owned, with display
      color). Unlocks fifth-aspect projects like Determination.
- [ ] Community enrichment (non-creators proposing metadata fixes).

## Open questions

- Ambition: personal-plus vs. THE community hub — the hub path means
  courting the Homebrew Discord / Hall of Heroes early (social buy-in
  mattered as much as tech for arkham.build and ALeP).
- Non-Marvel conversions (DC, TMNT, He-Man…): big popular slice, but
  multiplies third-party-IP surface. arkham.build's answer: banned from
  the public directory, fine via private import.
- Storage limits/quotas per user for uploads (Tigris cost control).

## Standing constraints (don't regress these)

- No monetization anywhere on surfaces hosting game IP — no donation
  links, no paywalls (Asmodee's 2024 policy names these explicitly).
- Never require metadata beyond the image — the image is the card.
- Never host bulk-downloadable packs of official card scans; homebrew
  upload must not become a proxy channel for official cards.
- Homebrew writes are user-scoped through policies — never through the
  `authorize?: false` system-write paths used by catalog sync.
- Private customs must never leak into other users' browse/search/game
  surfaces.
