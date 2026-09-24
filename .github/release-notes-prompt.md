# Write release notes for Sanctum

You are writing short, friendly, non-technical release notes for players of
Sanctum. Sanctum is a web-based "smart table" for playing Marvel Champions:
The Card Game online — decks, the card browser, games, scenarios, and a
card-guessing mini-game. Your readers are players, not developers.

## Inputs

The **Release context** section below gives you `Tag`, `Date`, `Commit
range`, and `Output file`. The **Changelog** section is a conventional-commit
bullet list covering that commit range. It may be empty (manual backfills) —
if so, rely on git directly.

## Research

If a changelog bullet is unclear or you need more detail to describe the
player-facing effect accurately, investigate with `git log <range>`, `git
show <sha>`, and `git diff <range> -- <path>`, and read the relevant source
files. The changelog links to short SHAs — look those up. Read `CLAUDE.md`
for product context (routes, domains, what's admin-only).

## Output

Write exactly ONE file, at the `Output file` path given in the Release
context section. Do not create, edit, or delete any other file. Do not run
git commands that change state (no commit, checkout, or add).

### Exact file format

No YAML frontmatter. Example:

```
Date: 2026-09-18

## New
- Deck pages now show a chart of your deck's aspect and card-type breakdown.

## Fixed
- The opening-hand simulator no longer overlaps the decklist on phones.
```

- Line 1 is `Date: <the Date given in Release context>`, used verbatim.
- Line 2 is blank. The body follows.
- Headings are exactly `## New`, `## Improved`, `## Fixed`, in that order.
  Omit any heading that has no bullets. No other headings, no H1, no title,
  no version number — the site shows the tag separately.
- Use short `- ` bullets, one idea each, in plain player-facing language.
  Describe what the player can now do or see differently, not what the code
  does. No commit hashes, scopes, file or module names, PR links, or jargon
  ("LiveView", "Ash", "migration", "FK", "resource", "endpoint", "refactor").
- Map `feat` commits to New (or Improved, if they enhance something that
  already existed). Map `fix` commits to Fixed. Merge related bullets into
  one when they describe the same player-visible change.

### Drop entirely

- `chore`, `ci`, `build`, `refactor`, `test`, and `perf`/`style` changes with
  no visible effect, and `docs` changes.
- Dependency bumps.
- Internal data-model or schema changes with no visible effect.
- Anything admin-only: `/admin/*` pages, card sync, the Oban dashboard,
  AshAdmin, and any feature gated behind `User.admin`. `/homebrew` is
  currently admin-only (see the comment in `lib/sanctum_web/router.ex`) —
  treat it as internal until that changes.
- Dev tooling: `mix` tasks, scripts, `prod_local`, vision eval.

### Worked examples

- "CardSide.aspect_def FK to Aspect (phase 2a)" → omit; this is internal. If
  it's the only change in the release, the result is the sentinel below.
- "MarvelCDB-style deck charts on both deck surfaces" → "Deck pages now show
  a chart of your deck's aspect and card-type breakdown."
- "tts: bag-name resolution layer for Hitch's TTS mod" → judge from the code
  whether players actually see this. If it's not user-visible, omit it.

### Sentinel

If nothing in the release qualifies as user-facing, the output file must
contain exactly this single line and nothing else (no `Date:` line, no
trailing content):

```
NO_USER_FACING_CHANGES
```

Never write an empty or near-empty notes file instead of using the sentinel.

Do not ask questions; you are running non-interactively. When the file is
written, stop.
