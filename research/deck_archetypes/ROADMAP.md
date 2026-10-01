# Deck Archetypes — where this goes next

Status and forward plan for the deck-archetype work. The harness itself is
documented in `README.md`; this doc is about **what we learned**, **what to do
next in the research**, and **how to land these as real app features**.

## What we have (validated)

- An offline Python harness (`research/deck_archetypes/`) that turns a snapshot
  of the deck corpus into deck representations, clusters/decomposes them, and
  scores the result against a label-free metric (held-out card prediction) plus
  a hand-seeded anchor set. Config-driven; every run lands on a hashed leaderboard.
- An Elixir export (`mix sanctum.export_deck_corpus`) that dumps the corpus to
  NDJSON, including `hero_locked` (signature-card exclusion) and per-hero base
  stats + ability text.

### Findings that shape the plan

1. **Cluster within aspect.** A global run mostly rediscovers the aspect split
   (18/20 clusters ≥94% one aspect). Within-aspect (still cross-hero) is where
   the real archetype structure lives.
2. **Package archetypes are soft, not hard.** "Firepower" never forms its own
   hard cluster — HDBSCAN/kmeans file it under whichever bigger family
   (S.H.I.E.L.D., attack-tempo) each deck belongs to. **NMF soft-membership
   recovers it cleanly**: a "firepower topic" that the firepower anchor decks
   load 0.71 on. Package/theme archetypes want *mixed membership*; deck
   *families* want hard clustering.
3. **Playstyle is computable.** A per-deck Damage/Threat/Survivability/Economy/
   Card-Drawing/Complexity profile derived from card stats + text + hero, tuned
   against 96 human-rated writeups (mean Spearman 0.37).

## Research next steps

- **Run on prod data.** Everything so far is the dev snapshot. Point the export
  at a `pull_prod_db` dump / `prod_local` and re-run; the distribution is the
  real target.
- **Enumerate the topic taxonomy.** Run NMF per aspect over the full corpus,
  name the topics (firepower, S.H.I.E.L.D. allies, thwart-control, big-ally
  beatdown, …), and capture them as a stable **archetype catalog**. This catalog
  is the artifact the app consumes.
- **Turn on the text-embedding channel.** It's wired but off in the fast configs
  (needs `sentence-transformers`). Ablate it on the held-out metric — it should
  help rare cards and could sharpen the weak playstyle dims.
- **Strengthen the anchor set.** More decks per archetype, and ≥2 archetypes per
  aspect partition, so `deck_precision` is a real discriminator (with one label
  per partition it is trivially 1.0).
- **Improve the weak playstyle dimensions.** Card Drawing (0.29) and Complexity
  (0.27) lag; keyword matching is crude. Try deriving them from the rules-text
  embedding instead of hand-keywords, and re-check with `calibrate_playstyle.py`.

## App integration

Two shippable features fall out of this, at very different readiness levels.

### 1. Playstyle breakdown on deck pages — closest to ship

No clustering or taxonomy needed; it's a **deterministic function** of a deck's
cards + hero. This reproduces the star-rating table MarvelCDB writeups include,
auto-generated, no LLM.

- **Port the scorer to Elixir** — a `Sanctum.Decks.Playstyle` module mirroring
  `analysis/playstyle.py`: per-card contribution weights + hero-identity term →
  6 raw dimension scores.
- **Stars need corpus-relative cutpoints.** Precompute the quintile thresholds
  per dimension from the whole deck corpus in an Oban job (sibling to
  `ComputeUniquenessWorker`), store them (small table or app config), and map a
  deck's raw score → 1–5 stars against them. Recompute on the same cadence as
  uniqueness.
- **Cache or compute live.** Scores are cheap; either compute on the deck page
  or cache onto the deck (like `uniqueness_score`) via the same worker.
- **Render** on the deck show page as a compact stars block. Bonus: show it on
  deck tiles and let users sort/filter ("high survivability protection decks").
- **Guardrail:** keep `calibrate_playstyle.py` as a regression check — if the
  Elixir port drifts from the Python scorer, correlation to the 96 rated decks
  drops.

### 2. Archetype tags + browser filter — needs the taxonomy first

- **Freeze the topic model in Python, serve in Elixir.** Training NMF is a
  Python/offline job; don't reimplement it in Elixir. Instead export the learned
  topic definitions (the `H` matrix: topic → card weights) + the named catalog,
  and in the app **project each deck onto the frozen topics** — a cheap matrix
  op (Nx) that yields per-deck loadings `W`. Retrain in Python only when the card
  pool grows meaningfully.
- **Data model:** a `DeckArchetype` join (deck ↔ archetype, with a loading), or
  a jsonb `archetypes` list on the deck. Written by an Oban worker that projects
  decks onto the current topic model.
- **Surface:** soft tags on deck tiles/pages — "Firepower (55%), Aggression
  tempo (30%)" — and an archetype facet in the deck browser alongside hero/aspect
  (reuse the existing `Sanctum.Search.DeckFields` filter machinery).
- **Alternative for named archetypes: signature detectors.** For well-known
  archetypes, a simple explainable rule ("contains ≥N of the firepower core
  set") is more precise and needs no ML in prod. Use NMF for *discovery* and to
  seed the catalog; use signature rules for *labeling* the ones we choose to name.

### Recommended architecture

**Two tiers.** Python owns *discovery and training* (offline, periodic, on prod
snapshots); Elixir owns *serving* (deterministic playstyle scoring; projecting
decks onto a frozen topic model; signature-rule labeling). The heavy/experimental
work stays in this harness; only lightweight, frozen scorers/projectors ship.

The export task is the Python→app bridge already; the missing piece is a small
**import** path (topic `H` matrix + playstyle cutpoints + archetype catalog) that
the serving jobs read.

## Suggested sequence

1. **Ship the playstyle breakdown** — best value/effort, no taxonomy dependency.
2. **Finalize the NMF topic taxonomy on prod data** and name the archetypes.
3. **Ship archetype tags + a browser facet**, projecting decks onto the frozen
   topics (plus signature rules for the marquee archetypes).
