"""Turn a raw snapshot into a modelling-ready Corpus.

Applies the corpus/card filters, builds the deck×card sparse count matrix and
the index maps every downstream stage shares, and precomputes per-card IDF
(staple down-weighting). Cost buckets are attached to the card table here so
features and structural summaries agree on bucketing.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import polars as pl
from scipy import sparse

from .config import get


@dataclass
class Corpus:
    cards: pl.DataFrame  # kept cards, row i == vocabulary index i
    decks: pl.DataFrame  # kept decks, row j == deck index j
    X: sparse.csr_matrix  # [n_decks, n_cards] quantity counts
    card_ids: list[str]
    deck_ids: list[str]
    card_index: dict  # card_id -> col
    deck_index: dict  # deck_id -> row
    idf: np.ndarray  # [n_cards] log(N / df)
    card_weight: np.ndarray  # [n_cards] per-card multiplier (aspect_downweight)
    cost_bucket_edges: list[int]

    @property
    def n_decks(self) -> int:
        return self.X.shape[0]

    @property
    def n_cards(self) -> int:
        return self.X.shape[1]

    def binary(self) -> sparse.csr_matrix:
        b = self.X.copy()
        b.data[:] = 1.0
        return b


def build_corpus(snapshot, cfg, restrict_aspects=None) -> Corpus:
    edges = list(get(cfg, "representation.card_features.cost_bucket_edges", [0, 1, 2, 3, 4, 6]))

    decks = filter_decks(snapshot.decks, cfg, restrict_aspects=restrict_aspects)
    cards = _filter_cards(snapshot.cards, cfg)
    cards = _attach_cost_bucket(cards, edges)

    deck_ids = decks["deck_id"].to_list()
    deck_set = set(deck_ids)
    card_set = set(cards["card_id"].to_list())

    dc = snapshot.deck_cards.filter(
        pl.col("deck_id").is_in(deck_set) & pl.col("card_id").is_in(card_set)
    )

    # Rarity floor: drop cards appearing in fewer than min_deck_count kept decks,
    # then drop any deck left with no chosen cards.
    min_dc = int(get(cfg, "card_filter.min_deck_count", 3))
    df = dc.group_by("card_id").agg(pl.col("deck_id").n_unique().alias("df"))
    keep_cards = set(df.filter(pl.col("df") >= min_dc)["card_id"].to_list())
    cards = cards.filter(pl.col("card_id").is_in(keep_cards))
    card_set = set(cards["card_id"].to_list())
    dc = dc.filter(pl.col("card_id").is_in(card_set))

    decks = decks.filter(pl.col("deck_id").is_in(set(dc["deck_id"].unique().to_list())))
    deck_ids = decks["deck_id"].to_list()

    card_ids = cards["card_id"].to_list()
    card_index = {c: i for i, c in enumerate(card_ids)}
    deck_index = {d: j for j, d in enumerate(deck_ids)}

    rows = np.fromiter((deck_index[d] for d in dc["deck_id"].to_list()), dtype=np.int64)
    cols = np.fromiter((card_index[c] for c in dc["card_id"].to_list()), dtype=np.int64)
    vals = np.asarray(dc["quantity"].to_list(), dtype=np.float64)
    X = sparse.csr_matrix((vals, (rows, cols)), shape=(len(deck_ids), len(card_ids)))

    n = X.shape[0]
    doc_freq = np.asarray((X > 0).sum(axis=0)).ravel()
    idf = np.log(n / np.maximum(doc_freq, 1))
    card_weight = _card_weight(cards, cfg)

    return Corpus(
        cards=cards,
        decks=decks,
        X=X,
        card_ids=card_ids,
        deck_ids=deck_ids,
        card_index=card_index,
        deck_index=deck_index,
        idf=idf,
        card_weight=card_weight,
        cost_bucket_edges=edges,
    )


def aspect_counts(snapshot, cfg) -> dict:
    """Aspect -> deck count over the (non-aspect) corpus filters. Used to decide
    which aspects to partition on. A deck contributes to each aspect it lists."""
    decks = filter_decks(snapshot.decks, cfg)  # no aspect restriction
    exploded = decks.select(pl.col("aspects").explode()).drop_nulls()
    if exploded.height == 0:
        return {}
    vc = exploded["aspects"].value_counts()
    return dict(zip(vc["aspects"].to_list(), vc["count"].to_list()))


def filter_decks(decks: pl.DataFrame, cfg, restrict_aspects=None) -> pl.DataFrame:
    out = decks
    for field in ("state", "visibility", "source"):
        allowed = get(cfg, f"corpus.{field}")
        if allowed:
            out = out.filter(pl.col(field).is_in(list(allowed)))
    min_size = get(cfg, "corpus.min_deck_size")
    if min_size:
        out = out.filter(pl.col("size") >= int(min_size))

    # Aspect scoping: explicit partition (restrict_aspects) wins over a config
    # corpus.aspects filter. A deck matches if any of its aspects is allowed.
    allowed = restrict_aspects or get(cfg, "corpus.aspects")
    if allowed:
        allowed = list(allowed)
        out = out.filter(
            pl.col("aspects").list.eval(pl.element().is_in(allowed)).list.sum() > 0
        )
    return out


def _card_weight(cards: pl.DataFrame, cfg) -> np.ndarray:
    """Per-card multiplier. `representation.aspect_downweight` (< 1) shrinks the
    pull of aspect-specific cards so a cross-aspect run surfaces aspect-crossing
    (basic-card / structural) archetypes instead of rediscovering the aspects."""
    w = np.ones(cards.height)
    downweight = get(cfg, "representation.aspect_downweight")
    if downweight is not None and float(downweight) < 1.0:
        has_aspect = np.array([a is not None for a in cards["aspect"].to_list()])
        w[has_aspect] = float(downweight)
    return w


def _filter_cards(cards: pl.DataFrame, cfg) -> pl.DataFrame:
    out = cards
    if get(cfg, "corpus.strip_hero_cards", True):
        # ownership==hero catches most; hero_locked (card.set == a hero's set)
        # also catches aspect-flavored signature cards (e.g. Spider-Woman's
        # Pheromones, ownership=player) that appear in ~100% of that hero's decks.
        out = out.filter(pl.col("ownership") != "hero")
        if "hero_locked" in out.columns:
            out = out.filter(~pl.col("hero_locked").fill_null(False))
    return out


def _attach_cost_bucket(cards: pl.DataFrame, edges: list[int]) -> pl.DataFrame:
    # Bucket index = number of edges the (0-clamped) cost meets or exceeds, minus 1.
    def bucket(cost):
        if cost is None:
            return len(edges) - 1  # treat unknown cost as top bucket (rare)
        b = 0
        for i, e in enumerate(edges):
            if cost >= e:
                b = i
        return b

    return cards.with_columns(
        pl.col("cost")
        .map_elements(bucket, return_dtype=pl.Int64, skip_nulls=False)
        .alias("cost_bucket")
    )
