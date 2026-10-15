"""Channel C — structured per-card feature vectors, aligned to the vocabulary.

One row per card in `corpus.card_ids` order. Grounds rare cards (which get poor
co-occurrence vectors) and gives the fused card embedding a semantic backbone
complementary to the rules-text channel.
"""

from __future__ import annotations

import numpy as np

from ..config import get


def build(corpus, cfg):
    """Return (matrix [n_cards, d], feature_names)."""
    cards = corpus.cards  # vocab order
    inc = get(cfg, "representation.card_features.include")
    blocks, names = [], []

    def want(attr):
        return bool(getattr(inc, attr, False)) if inc is not None else False

    if want("type"):
        m, n = _onehot(cards["type"].to_list(), "type")
        blocks.append(m)
        names += n
    if want("ownership"):
        m, n = _onehot(cards["ownership"].to_list(), "own")
        blocks.append(m)
        names += n
    if want("aspect"):
        m, n = _onehot(cards["aspect"].to_list(), "aspect")
        blocks.append(m)
        names += n
    if want("traits"):
        m, n = _multihot(cards["traits"].to_list(), "trait")
        blocks.append(m)
        names += n
    if want("cost"):
        blocks.append(_col(cards["cost"].to_list()))
        names.append("cost")
    if want("resource_icons"):
        for c in ("resource_physical", "resource_mental", "resource_energy", "resource_wild"):
            blocks.append(_col(cards[c].to_list()))
            names.append(c)
    if want("stats"):
        for c in ("atk", "thw", "def", "hp"):
            blocks.append(_col(cards[c].to_list()))
            names.append(c)

    if not blocks:
        return np.zeros((corpus.n_cards, 0)), []
    return np.hstack(blocks), names


def _col(values):
    arr = np.array([0.0 if v is None else float(v) for v in values], dtype=np.float64)
    return arr.reshape(-1, 1)


def _onehot(values, prefix):
    cats = sorted({v for v in values if v is not None})
    idx = {c: i for i, c in enumerate(cats)}
    m = np.zeros((len(values), len(cats)), dtype=np.float64)
    for r, v in enumerate(values):
        if v in idx:
            m[r, idx[v]] = 1.0
    return m, [f"{prefix}={c}" for c in cats]


def _multihot(list_values, prefix):
    vocab = sorted({t for lst in list_values for t in (lst or [])})
    idx = {t: i for i, t in enumerate(vocab)}
    m = np.zeros((len(list_values), len(vocab)), dtype=np.float64)
    for r, lst in enumerate(list_values):
        for t in lst or []:
            m[r, idx[t]] = 1.0
    return m, [f"{prefix}={t}" for t in vocab]
