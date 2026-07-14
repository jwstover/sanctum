# Marvel Champions Online (Sanctum)

A web-based "smart table" for playing Marvel Champions: The Card Game online. It
provides digital deck and game-state management — zones, tokens, card states —
**without enforcing game rules**; players enforce the rules themselves. Built for
personal use, designed with room to grow into multiplayer.

## Rules for Working in This Repo

- **NEVER modify migrations manually.** Migrations are managed by Ash — generate
  them with `mix ash.codegen <name>`. The rare exception is framework-shipped
  migrations (e.g. an `Oban.Migration.up(version: N)` when bumping Oban across a
  schema version); those are added by hand deliberately.
- **Ash is the source of truth for the data layer.** Resources define attributes,
  relationships, actions, and policies. Don't hand-write Ecto schemas or raw SQL
  migrations to model domain data — change the resource and run codegen.
- **Single dark theme.** The UI is a pinned dark "comic-dossier" design. There is
  no light/dark toggle — do not reintroduce daisyUI theme switching.

## Technical Stack

- **Backend**: Elixir/Phoenix, **Ash Framework** (resources, policies, actions)
- **Frontend**: Phoenix LiveView + Tailwind + custom JS hooks; self-hosted fonts
- **Database**: PostgreSQL (Neon in prod). The database is the authoritative source
  of state — there is no in-memory game process.
- **Real-time**: Phoenix PubSub
- **Background jobs**: Oban + AshOban
- **Deploy**: Fly.io (Depot builder), card images on a public Tigris S3 bucket

## Architecture

State lives in **Postgres, modeled with Ash resources**, and is rendered/mutated
directly by LiveViews. There is **no GenServer-per-game** — games are plain Ash
resources. PubSub broadcasts changes to connected clients. The only long-lived
process is `Sanctum.CardSync.Server` (drives MarvelCDB catalog sync).

### Ash Domains

| Domain | Purpose |
|---|---|
| `Sanctum.Accounts` | Users + tokens; auth (Google OAuth, magic link, password). `User.admin` boolean gates admin surfaces. |
| `Sanctum.Games` | Cards, card sides, scenarios, and live game state. The core domain. |
| `Sanctum.Decks` | Player decks imported from MarvelCDB; deck cards, aspects, uniqueness. |
| `Sanctum.Heroes` | Hero catalog (incl. `meta.colors`-derived gradient palette). |
| `Sanctum.Villains` | Villain catalog. |

### Card Data Model

MarvelCDB's card representation is normalized into:

- **`Card`** — the canonical card (`code`, `base_code`, `set`, `pack`,
  `deck_limit`, `unique`, `permanent`, `is_multi_sided`). Has many `card_sides`,
  a `primary_side`, many `alts`, and `many_to_many :decks`.
- **`CardSide`** — one face of a card (identity/alter-ego, main-scheme A/B, etc.).
  Holds the printed data: `name`/`subname`, `traits`, `type`, `ownership`,
  `aspect`, `text`, `image_url`, and the game stats.
- **`CardAlt`** — reprints. MarvelCDB's ~336 duplicate printings collapse into
  `CardAlt` rows pointing at the canonical `Card`; deck slots resolve reprint
  codes through the alt fallback.

Key type/field conventions:

- **`Stat`** (`Sanctum.Games.Stat`) — a **custom `Ash.Type`** (NOT an embedded
  resource) stored as jsonb: `%{value, star, scaling}`. Used for `attack`,
  `thwart`, `defense`, `health`, `recover`, and the threat stats. `cast_input`
  accepts a bare number or a map, so sync/fixtures/forms all work.
- **`CardOwnership`** enum (`:player | :basic | :pool | :hero | :encounter |
  :campaign`) and a separate nullable **`CardAspect`** enum (4 aspects only) —
  this replaced MarvelCDB's overloaded `faction_code`.

Live game state (`Game`, `GamePlayer`, `GameCard`, `GameVillain`,
`GameEncounterDeck`, `Scenario`, `ModularSet`): `GameCard` is the single
representation of an in-play card in any zone (main scheme, side scheme, player
area, etc.) — a prior separate `GameScheme` was folded into it.

## Subsystems

- **MarvelCDB sync** — `mix sanctum.sync_cards` / `mix sanctum.sync_decks` (dev)
  and `Sanctum.Release.sync_cards()` (prod, data-only). Card sync also runs
  interactively from the `/cards/sync` admin LiveView, backed by
  `Sanctum.CardSync.Server` (GenServer + `Task` broadcasting throttled progress
  over PubSub). Sync groups payload entries per `base_code` to resolve sides
  (MarvelCDB's `linked_to_code` chains are incomplete). See `lib/sanctum/marvel_cdb.ex`.
- **Card images** — mirrored once from MarvelCDB into a public Tigris bucket
  (`sanctum-cards`); `card_sides.image_url` stores full bucket URLs. See
  `lib/sanctum/card_images.ex`.
- **Deck import** — decks come from MarvelCDB; Oban workers handle sync
  (`decklist_sync_worker`) and uniqueness computation (`compute_uniqueness_worker`).
- **Admin lockdown** — all `/cards/*` management routes live in an `:admin_routes`
  live session behind a `:live_admin_required` on_mount hook (`User.admin`), plus
  admin-only Card/CardSide mutation policies (reads are open). Bootstrap the first
  admin with `Sanctum.Release.promote_admin(email)`. System writes (sync, seeds,
  deck import) run with `authorize?: false`.
- **Design system** — the pinned dark "comic-dossier" theme: self-hosted fonts,
  design tokens, halftone/offset-shadow utilities, an app shell, and the `mc_card`
  component. See `lib/sanctum_web/components`.

### Routes (authenticated)

- `/` — `GameLive.Index` (games list); `/games/new`, `/games/:id`
- `/cards` — `CardLive.Pool` (card browser, public read)
- `/decks`, `/decks/:id` — deck browser
- `/guess` — `GuessLive.Play` (card-guessing mini-game)
- `/cards/manage`, `/cards/new`, `/cards/sync`, `/cards/:id/edit` — **admin only**

## Development Commands

The dev server runs on **port 4150** (not the usual Phoenix `4000`) — reach it at
`http://localhost:4150`.

```bash
mix setup                    # deps, database, assets
iex -S mix phx.server        # dev server with console (http://localhost:4150)

mix ash.codegen <name>       # generate migrations after resource changes
mix ash.setup                # set up Ash resources + database
mix ecto.reset               # drop + recreate database

mix sanctum.sync_cards       # sync card catalog from MarvelCDB (dev)
mix sanctum.sync_decks       # sync decks from MarvelCDB (dev)

mix test                     # test suite (runs ash.setup quietly)
mix ck                       # format + Credo + Sobelow (run before committing)
mix format                   # format only
mix dialyzer                 # static analysis (PLTs in priv/plts/)
```

## Dev Dashboards

- `/dev/dashboard` — Phoenix LiveDashboard
- `/oban` — Oban job monitoring
- `/admin` — AshAdmin resource management
- `/dev/mailbox` — email preview

## Notes

- **Detailed decision history** (entity redesigns, card model v2, image sourcing,
  admin lockdown, design migration, CI/deploy fixes) lives in the Obsidian vault
  under `01 - Projects/Personal/Sanctum/` — consult it before large changes rather
  than duplicating that context here.
- Auth: Google OAuth registration is **open** (any Google account can sign in), so
  authentication ≠ trust — the `User.admin` flag is what gates privileged surfaces.
- `docs/card_fields.md` and `docs/card_model_v2.md` document the card data model
  and its most recent redesign.
