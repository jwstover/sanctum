# Deck Archetype Discovery — experimentation harness

Offline, throwaway research scaffolding for discovering **cross-hero deck
archetypes** (e.g. "Firepower", "cheap-ally aggro", "splashy-finisher control")
by clustering learned deck representations.

This is **not** production code. The plan is: iterate here in Python against a
frozen snapshot of the real deck corpus, find a recipe that scores well on the
eval harness, then port only the winning recipe into an Elixir Oban batch job
(sibling to `Sanctum.Decks.ComputeUniquenessWorker`) that writes archetype
membership onto decks.

## The one idea that organizes everything

There are **no ground-truth labels**. So "run B is better than run A" has to be a
number, or you're just eyeballing t-SNE forever. Every design decision here is
subordinate to the eval harness (`evaluation/`), which produces a leaderboard.
The primary automatic metric is **held-out card prediction** (label-free); the
secondary is **anchor retrieval** against a small hand-seeded gold set. Only
after those agree do we trust human cluster inspection.

## Pipeline

```
[Export]  (Elixir mix task, in the main repo)
    │   mix sanctum.export_deck_corpus --out research/deck_archetypes/snapshots/<date>
    ▼
snapshots/<date>/            immutable, hashed parquet snapshot
    │
    ▼
[Preprocess]  corpus + card filters, cost bucketing, canonicalization asserts
    │
    ▼
[Representation]  build ONE card vector per card, then pool into deck vectors
    │   ├─ Channel A  distributional  (co-occurrence: ppmi_svd | word2vec | nmf)
    │   ├─ Channel B  text            (rules-text sentence embeddings)
    │   └─ Channel C  card_features   (structured per-card: cost/type/traits/stats)
    │   fusion → card vectors → pooling (Channel 1)
    │   + structural deck summary      (Channel 2 — the deck's *shape*)
    │   channel normalize + weight (β) → deck vectors
    ▼
[Clustering]  hdbscan | louvain | kmeans | nmf_topics
    │
    ▼
[Evaluation]  held_out prediction · anchor retrieval · intrinsic · projection · interpret
    │
    ▼
[Report]  runs/<name>/ + append to runs/leaderboard.parquet   (keyed by snapshot+config hash)
```

Every stage is config-driven and swappable. An **experiment == a config file**
(`configs/*.yaml`). See `configs/baseline.yaml` for the full annotated knob
surface; every channel is independently ablatable so you can measure what each
is worth.

## Two channels make up a deck vector

This is the subtle part. A deck vector is the concatenation of:

1. **Pooled card embeddings** — weighted mean of fused per-card vectors.
   Captures *which cards / what roles*.
2. **Structural summary** — explicit deck-level features (cost×type crosstab,
   type mix, trait distribution, cost concentration, ally stat-efficiency…).
   Captures *the deck's statistical shape* — "cheap allies", "few splashy
   finishers". **Mean-pooling alone destroys this**, which is why it's a
   separate channel. Locked feature list lives in `features/structural.py` and
   is toggled in `deck_vector.structural` in the config.

The two channels are z-scored independently, then weighted by `β_embedding` /
`β_structural` (swept), then L2-normed. `β_structural` is expected to be one of
the highest-leverage knobs.

## Export contract (Elixir → NDJSON)

The `mix sanctum.export_deck_corpus` task (in the main repo, `lib/mix/tasks/`)
writes three newline-delimited JSON files into a dated snapshot dir. Alt reprints
are resolved to the **canonical** card id *in the export query* so Python never
sees a reprint code.

- `decks.jsonl` — `deck_id, hero_id, aspects[], state, visibility, source, size`
- `deck_cards.jsonl` — `deck_id, card_id (canonical), quantity`
- `cards.jsonl` — `card_id (canonical), name, type, ownership, aspect, traits[],
  cost, set, hero_locked, resource_physical/mental/energy/wild, atk, thw, def,
  hp, text`

`hero_locked` marks cards whose `set` is a hero's signature set. It catches
signature cards that are **not** `ownership==hero` — the aspect-flavored ones
(e.g. Spider-Woman's Pheromones, `ownership=player`, `aspect=leadership`) that
sit in ~100% of that hero's decks and would otherwise pollute clusters.
`strip_hero_cards` drops both `ownership==hero` and `hero_locked`.

A `SNAPSHOT.json` alongside them stamps row counts + `max(updated_at)` as the
`snapshot_hash` so runs against different corpora never get compared.

Run it against `prod_local` or a `pull_prod_db` dump so you iterate on the real
deck distribution.

## Aspect scoping (within-aspect is the default)

Most heroes build a single aspect, so archetypes live inside one — a global run
mostly rediscovers the aspect partition (measured: 18/20 global clusters were
≥94% one aspect). So `corpus.partition_by: aspect` is the default: one
independent clustering run per aspect (still cross-*hero*), written to
`runs/<name>/<aspect>/` with a leaderboard row per aspect.

Knobs:
- `corpus.partition_by: aspect | null` — per-aspect vs one global run.
- `corpus.partition_min_decks` — skip thin aspects.
- `corpus.aspects: [justice]` — pin a single aspect for a one-off.
- `representation.aspect_downweight` (< 1) — for a deliberate cross-aspect run
  (`partition_by: null`), shrinks aspect-specific cards' pull so aspect-crossing
  basic-card / structural archetypes surface instead of the aspects themselves.
  See `configs/cross_aspect.yaml` (drops mean aspect-purity ~97% → ~78%).

## Directory layout

```
research/deck_archetypes/
├── README.md                     ← this file
├── requirements.txt
├── configs/
│   └── baseline.yaml             ← the full locked knob surface
├── anchors/
│   └── archetypes.example.yaml   ← hand-seeded gold set for anchor retrieval
├── snapshots/                    ← parquet exports (gitignored; big)
├── runs/                         ← per-experiment outputs + leaderboard (gitignored)
├── run.py                        ← CLI: python run.py configs/baseline.yaml
└── src/deck_archetypes/
    ├── config.py                 ← load/validate yaml → dataclass, config hashing
    ├── snapshot.py               ← load parquet, assert canonicalization
    ├── preprocess.py             ← corpus/card filters, cost buckets
    ├── features/
    │   ├── card_features.py      ← structured per-card vectors (Channel C)
    │   ├── text_embed.py         ← rules-text embeddings (Channel B)
    │   └── structural.py         ← deck-level structural summary (Channel 2) ★locked
    ├── representation/
    │   ├── base.py               ← Representation protocol (swappable backbones)
    │   ├── ppmi_svd.py · word2vec.py · nmf.py
    │   └── fusion.py             ← channel normalize + weight + pool → deck vecs
    ├── clustering/
    │   ├── base.py               ← Clusterer protocol
    │   └── hdbscan_.py · louvain.py · kmeans.py
    ├── evaluation/
    │   ├── held_out.py           ← ★primary metric (label-free)
    │   ├── anchors.py            ← anchor retrieval vs gold set
    │   ├── intrinsic.py          ← silhouette / DB / bootstrap stability
    │   ├── interpret.py          ← top-lift cards + structural profile per cluster
    │   └── projection.py         ← UMAP 2D colored by aspect/hero/anchor/cluster
    ├── pipeline.py               ← wires stages from a config
    └── leaderboard.py            ← append run metrics
```

## Workflow

1. Freeze a snapshot (`mix sanctum.export_deck_corpus`).
2. Seed `anchors/archetypes.yaml` — 5–10 archetypes, a few known decks and/or
   core cards each. 30 minutes; massively de-risks eval.
3. Run the baselines already in `configs/` — **always keep the dumb baselines**
   (random init, bag-of-cards + TF-IDF cosine) on the leaderboard so you know
   whether embeddings are earning their complexity.
4. Sweep weights/channels against held-out prediction + anchor retrieval.
5. Take the top few by metric, *then* inspect clusters/top-cards/UMAP to confirm
   they're human-sensible, not metric-gaming.
6. Promote the winning recipe → port to an Elixir batch job.

The corpus is tiny by ML standards (~50k short "documents", a few hundred
relevant cards) — the whole pipeline runs in seconds on CPU. Exploit that with
wide sweeps.
