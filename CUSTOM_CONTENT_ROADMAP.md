# Custom Content Roadmap

Working checklist for hosting community custom (homebrew) content in Sanctum.
Research and decision context: Obsidian vault under
`01 - Projects/Personal/Sanctum/` (see
`research/2026-07-20-custom-content-landscape.md`).

**Status (2026-07-22):** sections 1–2 are shipped (minus the deferrals noted
inline) across PRs #266 (foundation), #284 (enrichment), and #281 (alt art +
card editor). The whole feature is **temporarily admin-gated** — the routes
live in the `:admin_routes` live session and the sidebar link hides from
non-admins; reopening is just moving the routes back to
`:authenticated_routes` (resource policies are creator-scoped and unchanged).
Next up: section 3, split into a player-card slice and a scenario slice.

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
- **New-aspect support pulled forward (2026-07-23).** Was deferred; now planned,
  because the custom-content metadata work kept hitting the one place
  non-conformance actually loses data (the vision extractor forcing `aspect`
  into the five-value enum). Convert `CardAspect`/`DeckAspect` into a data-driven
  `Aspect` lookup resource keyed on a **stable string `key`** (official keys =
  today's atom names, so the only pervasive change is atom→string).
  `CardSide.aspect` stays a string column + a `belongs_to :aspect_def`;
  `deck.aspects` becomes `{:array, :string}`; custom-aspect colors render via
  inline style (official keep compile-time `bg-aspect-*` utilities); custom
  aspects are project-scoped and inherit project visibility. Phased: Phase 1 is a
  zero-behavior-change refactor (official aspects only), Phase 2 is additive
  custom-aspect support. Full plan + touchpoint inventory in the Obsidian vault:
  `01 - Projects/Personal/Sanctum/plans/2026-07-23-aspect-as-resource.md`.
- **Alt art reuses `CardAlt`.** Custom alternate art for official cards is
  stored as `CardAlt` rows with an `origin` (`:official | :custom`)
  discriminator plus creator/project FKs — the uploader picks the target
  card, so `card_id` + `side_identifier` make the link concrete, and the
  art picker gets official reprint art (already in `CardAlt.image_url`)
  and custom uploads from one table. Custom rows get synthetic codes
  outside MarvelCDB's numeric space. Premise: full catalog wipes are
  retired as a maintenance technique. Custom card *backs* have no target
  card and are out of scope for CardAlt (defer).
- **Alt art is a CONVERSION, not a copy** (shipped in #281). Declaring a
  custom card as alt art destroys the Card/CardSide rows and mints the
  CardAlt (the card's `custom-<uuid>` code and image carry over); reverting
  mints a fresh image-only card named after the target. Enrichment metadata
  and artist credit are lost on the round trip — accepted, documented in
  the moduledocs and the declare sheet copy.
- **Privacy is filter read policies on Card/CardSide/CardAlt** (shipped in
  #266/#281), not per-surface filtering — card reads don't funnel through
  one path. Two hard-won Ash mechanics are load-bearing and documented at
  the policy sites: an `expr` referencing `^actor(:id)` collapses to false
  wholesale under a nil actor (keep OR branches as separate `authorize_if`
  checks), and on creates, policies run before `before_action` hooks (a
  create-time ownership check must resolve action *arguments*, not
  changeset attributes). Any `authorize?: false` READ must carry an
  explicit `origin == :official` filter (writeup resolver, signature
  cards, and CardAlt `by_code`/`by_codes` are pinned).
- **Card editing is a dedicated autosaving page** (`/homebrew/:id/cards/
  :card_id`), not a sheet — room for double-sided cards (each side's
  fieldset beside its art), per-input debounced autosave with a save-state
  indicator, and the card-shape actions (split, declare-as-alt) live there.
- **Temporary admin gate.** Until the feature is ready for public use, the
  homebrew routes sit in `:admin_routes` and the sidebar link is
  admin-only. Deliberately router-level only, so reopening is a route move
  with zero policy churn.
- **IP posture**: free-only (no monetization anywhere near hosted IP),
  "unofficial fan content" labeling, creator attestation on upload,
  © FFG / © MARVEL notices, working report/takedown flow. Asmodee's
  community-use policy explicitly blesses free fan cards/scenarios; the
  real risk vectors are money and Marvel art.

## 1. Data model & domain (`Sanctum.Homebrew`) — SHIPPED (#266, #281)

- [x] `HomebrewProject` resource — `creator` (User FK), `name`,
      `description` (markdown), `banner_url`, `content_types` (array enum:
      hero / villain_scenario / modular_set / campaign / aspect / other),
      `maturity` (:draft | :beta | :complete), `visibility`
      (:private | :unlisted | :published), tags, required `attestation`,
      `card_count`/`alt_count` aggregates. *Slug deferred* to the public
      directory (nothing routes by slug yet; projects route by UUID).
- [x] `Card.origin` enum (`:official | :custom`, default `:official`) +
      nullable `homebrew_project_id` FK (cascade on project delete) + a
      check constraint tying origin to project provenance.
- [x] Custom card codes: `custom-<uuid>`, outside the official
      `^[0-9]{5}[abcdef]?$` space (no collisions; sync upserts can neither
      capture nor collide with custom rows).
- [x] `CardSide` requirements for `:custom` origin — handled at the action
      layer, schema untouched: `create_custom` requires only `image_url`
      per side, autofills `name` from the filename, and mints codes/side
      identifiers; the narrow `:enrich` action makes everything else
      optional and editable forever (codes/identifiers/images can't be
      smuggled through it).
- [x] Policies: filter read policies on `Card`/`CardSide` (private
      invisible to others AND to actor-less reads — guess game, game
      setup; published visible to all); creator-scoped custom mutations;
      leak tests per read path (browse + counts, guessable, get-by-id,
      by-code, by-set, writeup resolution).
- [ ] Scenario support: homebrew projects can mint a set grouping (villain
      stages, main schemes, encounter cards with per-card `quantity`) that
      `Scenario`/game setup can consume like an official set. **Note from
      slice 1:** game-setup reads are actor-less today and correctly
      exclude customs — the game owner must be threaded through as actor
      when this lands. **Note from slice 2:** encounter `quantity` has no
      model yet (official encounter multiplicity = one Card row per copy;
      `deck_limit` is MarvelCDB's product quantity); needs a new attribute
      plus duplication in `create_game_encounter_deck`.
- [x] Alt art: `CardAlt.origin` discriminator + `creator_id` /
      `homebrew_project_id` FKs + artist credit; the custom alt keeps the
      source card's synthetic code; policy split on origin (reads: official
      always, custom published-or-own; mutations creator-scoped);
      `by_code`/`by_codes` and the writeup resolver pinned to `:official`.
      Declare/revert conversion flow + project-page management + "fan art ·
      by {artist}" captions on the card detail strip.
- [ ] `UserArtPreference` (user × card side → card_alt) applied at render
      via a preloaded map (hero-gradient pattern); art picker offers
      canonical image + official reprint art + published custom alts.
      Until this lands, alt art is display-only on the detail page.

## 2. Upload pipeline & enrichment UX — SHIPPED (#266, #284, #281)

- [x] LiveView batch upload (drag-drop PNG/JPG/WebP, 30 at a time) →
      Tigris `sanctum-cards` under the `homebrew/` prefix. Normalized via
      the existing image Processor; content-addressed `homebrew/<sha256>`
      keys, objects never overwritten — replacing art mints a new URL, so
      old games/snapshots keep rendering the original by construction.
- [x] Project page shows uploaded cards immediately — rendered with the
      pool's `card_side_tile` (degrades gracefully on missing metadata),
      with Edit/Delete actions in the tile's new `:actions` slot.
- [x] Enrichment (never required) on the dedicated autosaving edit page:
      name, subname, ownership, type (drives landscape orientation),
      aspect, cost, full stat axes (value + ★ + consequential damage on
      ATK/THW/DEF, scaling on HP, scheme + `scheme_star` — a new synced
      column), traits, text, flavor, deck limit, unique. *Encounter
      `quantity` deferred* to the scenario slice (no consumer exists yet).
- [x] Side pairing — pair mode on the project page selects two
      single-sided cards (front/back with swap) → one `is_multi_sided`
      card; the edit page splits them back apart.
- [ ] Grouping within a project: hero deck / encounter set / modular set
      buckets so game setup knows what shuffles where. *Deferred with the
      scenario slice.*
- [x] Upload attestation checkbox ("my work or shared with creator's
      permission") required at project creation.

### Google Drive import (ingestion source) — NOT STARTED

Creators ship homebrew as Drive folders (see the gap statement above), so
"import from a Drive link/folder" is a natural ingestion source feeding the
*existing* upload pipeline — the Processor, content-addressed
`homebrew/<sha256>` keys, and enrichment UX are all already built. The new
work is only *acquisition*: get the bytes from Drive into that pipeline. The
entire cost is dominated by **Google OAuth scope + app verification**, not
code — our current Google sign-in requests identity-only scopes
(`openid email profile`) and doesn't persist the access token, so any Drive
access is net-new consent + token plumbing.

Three approaches, cheapest → most powerful:

- [ ] **A. Public-share-link fetch (no OAuth scope) — recommended first.**
      Most homebrew Drives are "anyone with the link". Server enumerates +
      downloads with an API key (or unauthenticated for direct file links):
      `files.list` on the folder ID + `files.get?alt=media`, streamed into
      the existing homebrew Processor. New code: a `Sanctum.GoogleDrive`
      module (list + download), a URL/folder-ID parser, one LiveView "import
      from Drive link" field. **No verification, no CSP change, no token
      storage** — pure server-side `Req` calls; needs only a
      `GOOGLE_API_KEY` env var (or nothing for public direct links). Watch
      out for Drive's virus-scan interstitial on large files (needs the
      `confirm=` token dance). Limitation: public folders only, never a
      user's private Drive. ~1–2 days.
- [ ] **B. `drive.file` scope + Google Picker — private-Drive integration.**
      User connects Drive, the Picker UI lets them select specific
      files/folders, app gets access only to what was picked (the scope
      Google intends for this). New work beyond A: persist OAuth tokens with
      `offline` access + refresh-token storage (stock `UserIdentity` doesn't
      keep them), an incremental-authorization consent flow *separate from
      sign-in*, and the Picker JS — which loads `apis.google.com`, a **CSP
      change** we've deliberately avoided (single dark theme / self-hosted
      everything). Verification: `drive.file` is a *sensitive* scope →
      consent-screen verification (homepage, privacy policy, domain
      ownership, brand review), weeks of back-and-forth, **but no
      third-party audit.**
- [ ] **C. `drive.readonly` (full-Drive read) — avoid.** *Restricted*
      scope → triggers Google's annual CASA third-party security assessment
      (recurring money + overhead). Not justifiable for this app.

Notes:
- **Testing-mode escape hatch:** Google allows sensitive/restricted scopes
  for up to 100 allowlisted test users with *no* verification. While the
  homebrew feature is still admin-gated, approach B could ship without
  verification by adding creators as test users; verification only becomes
  mandatory when the feature opens broadly.
- **Recommendation:** ship A first — it matches how content is actually
  shared, reuses the whole pipeline, and sidesteps consent/tokens/CSP/
  verification entirely. Reach for B (with testing-mode allowlisting, not
  full verification) only if importing from *private* Drives is required.

## 3. Play integration (private-first MVP exit criteria) — NEXT

Recommended split: **3a (player cards)** then **3b (scenarios)**.

### 3a. Player-card slice

- [ ] Custom player cards appear in the owner's deckbuilder (advisory
      legality; degrade gracefully when cost/aspect absent).
- [ ] Decks containing custom cards build/save/render normally
      (`deck_source` distinguishes native already).
- [ ] Card browser/search: `origin:`/`official:` field in the search
      registry (registry-only change; the alt-art target picker already
      filters `card.origin == :official` server-side and could switch to
      it); own private customs visible only to self (already enforced by
      the read policies — this is about making them *findable*).
- [ ] Friendly referential-integrity handling: `DeckCard`/`GameCard` card
      FKs have no cascade, so deleting / pairing / declaring-as-alt a
      custom card that a deck references will raise a raw FK error today —
      convert to a "card is used in a deck" validation (`TODO(play-slice)`
      markers sit in `PairCustomCard` and `DeclareAltArt`).

### 3b. Scenario slice

- [ ] Set grouping + encounter `quantity` (see §1 scenario note).
- [ ] Custom scenario playable at the owner's table: villain stages,
      schemes, encounter deck built from quantities; missing stats mean
      players set tokens manually (player-enforced rules, by design).
      Requires threading the game owner as actor through game-setup reads.

### Also before public launch

- [ ] Remove the temporary admin gate (move the three homebrew routes back
      to `:authenticated_routes`; unhide the sidebar link; restore
      non-admin LiveView test actors).

## 4. Publish & discovery

- [ ] Publish flow: `:private → :unlisted (share link) → :published`
      (directory). Each publish creates a `ProjectRelease` (version,
      changelog, jsonb card-data snapshot). The `set_visibility` action is
      already separate from general editing so this can hang off it;
      unlisted share links need a dedicated read action (the global read
      filter stays private-by-construction).
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
- [x] "Unofficial fan content" labeling on homebrew surfaces (project
      pages carry it; the footer carries the non-affiliation + © notices).
      Revisit coverage when the public directory lands.

## 5. Ecosystem (later)

- [ ] Card Maker JSON/ZIP importer (champions-card-maker.pages.dev) —
      structured import for creators using the community's flagship tool.
- [ ] Stable export/read API so other tools (Digital Edition, Cardtable,
      DragnCards) can consume Sanctum-hosted projects — the "become
      infrastructure" play; consider publishing the format (marvelsdb
      schema + project envelope).
- [ ] Print-sheet / MPC-ready export from a project.
- [ ] **Tabletop Simulator deck export from a project.** Generate an
      importable TTS Saved Object (`.json`) from a project's own cards so
      users can play homebrew on TTS — including dropping it onto community
      tables like Hitch's Table (Workshop `2514286571`). Shares the
      sprite-sheet packing engine with the print-sheet export; only the
      output wrapper differs (TTS JSON vs. PDF/MPC layout).
      - **Approach: standalone deck object, not a mod.** Emit a `DeckCustom`
        object the user spawns via TTS's local Saved Objects folder. TTS lets
        any object be dropped onto any table, so custom cards ride on top of
        Hitch's generic scripted infrastructure (villain mat + built-in HP
        counter, threat/HP on seat count) — the player parks a custom villain
        on the mat and uses its tools. **Not** a Workshop mod (can't automate
        per-user Steam publishing; a full self-contained table is also the
        DMCA-risk shape — full-game reproductions are what got MC TTS mods
        taken down) and **not** integration with Hitch's importer (his Lua
        importer is hardcoded to MarvelCDB's API + `^[0-9]{5}` code schema and
        rejects unknown decks; making it load Sanctum would require his
        cooperation or a fragile MarvelCDB-API impersonation, and custom
        `custom-<uuid>` codes collide with his expectations).
      - **Format** (TTS save spec): a deck is JSON with `DeckIDs` +
        `CustomDeck`, a dict of sprite **sheets** (`FaceURL`, `BackURL`,
        `NumWidth`, `NumHeight`, `UniqueBack`, `BackIsHidden`). Cards pack
        into grids, **max 10×7 = 70 per sheet**. Card ID =
        `sheet_number * 100 + grid_index` (index 0-based, left→right,
        top→bottom); hundreds place selects the sheet, remainder the cell.
        Prior art proving the format is routine: MCdeck and the community
        Card Maker both already export TTS saves from custom cards.
      - **Work item: the sprite-sheet packer** — pack `CardSide.image_url`
        images into grid sheets, upload the sheets to the `sanctum-cards`
        Tigris bucket (reuse the homebrew upload Processor), emit the JSON
        with correct IDs. Double-sided cards (`is_multi_sided` /
        `primary_side`) map to the `UniqueBack` / back-sheet fields — the
        model already has the data to drive front/back.
      - **Scope + IP:** export a project's *own* cards only — never mix
        official scans into the generated object (keeps it out of
        full-scan/bulk-pack territory; a custom-content-only deck is exactly
        what Asmodee's community-use policy blesses). Free, unofficial,
        attributed — same posture as the rest of the feature.
      - Research + feasibility writeup:
        [[2026-07-22-tts-mod-export-feasibility]].
- [ ] Native card editor (only if demand; arkham.build never built one).
- [~] New-aspect support: `CardAspect`/`DeckAspect` enums → `Aspect` lookup
      resource (official five seeded; homebrew aspects project-owned, with
      display color). Unlocks fifth-aspect projects like Determination. **Pulled
      forward from "later"** — see the decision in §"Decisions made" and the
      vault plan `plans/2026-07-23-aspect-as-resource.md`. Phase 1 (refactor,
      official-only) is a self-contained no-UX-change PR; Phase 2 adds custom
      aspects + the vision `custom_aspect` reconciliation.
- [ ] Community enrichment (non-creators proposing metadata fixes).

## Open questions

- Ambition: personal-plus vs. THE community hub — the hub path means
  courting the Homebrew Discord / Hall of Heroes early (social buy-in
  mattered as much as tech for arkham.build and ALeP).
- Non-Marvel conversions (DC, TMNT, He-Man…): big popular slice, but
  multiplies third-party-IP surface. arkham.build's answer: banned from
  the public directory, fine via private import.
- Storage limits/quotas per user for uploads (Tigris cost control).
- When to lift the admin gate — probably with 3a (the feature is usable
  end-to-end for player cards) rather than waiting for scenarios.

## Standing constraints (don't regress these)

- No monetization anywhere on surfaces hosting game IP — no donation
  links, no paywalls (Asmodee's 2024 policy names these explicitly).
- Never require metadata beyond the image — the image is the card.
- Never host bulk-downloadable packs of official card scans; homebrew
  upload must not become a proxy channel for official cards.
- Homebrew writes are user-scoped through policies — never through the
  `authorize?: false` system-write paths used by catalog sync.
- Private customs must never leak into other users' browse/search/game
  surfaces. Any `authorize?: false` READ must carry an explicit
  `origin == :official` filter.
- Content-addressed homebrew image objects are never deleted or
  overwritten (hashes may be shared across cards/projects/users).
