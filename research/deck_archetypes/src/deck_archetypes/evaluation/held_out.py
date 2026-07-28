"""Held-out card prediction — the PRIMARY, label-free fitness metric.

Hold one card out of each of a sample of decks; rank it among all candidate
cards by cosine to the query deck vector pooled from the *remaining* cards. A
representation that captured real deckbuilding structure ranks it high. Operates
on the fused card space (Channel 1 only) — the structural channel is card-blind
by construction, so it doesn't participate here.
"""

from __future__ import annotations

import numpy as np

from ..config import get
from ..representation import fusion


def evaluate(card_matrix, corpus, cfg, *, seed=42):
    n_decks = int(get(cfg, "evaluation.held_out_prediction.n_decks", 2000))
    ks = list(get(cfg, "evaluation.held_out_prediction.k", [1, 5, 10, 25]))

    rng = np.random.default_rng(seed)
    norm = _l2(card_matrix)
    rarity = fusion.pool_weight_vector(corpus, cfg)
    qmode = get(cfg, "deck_vector.pooling.quantity_weight", "sqrt")

    X = corpus.X.tocsr()
    candidates = min(n_decks, X.shape[0])
    deck_ids = rng.choice(X.shape[0], size=candidates, replace=False)

    ranks = []
    for j in deck_ids:
        cols = X.indices[X.indptr[j] : X.indptr[j + 1]]
        qty = X.data[X.indptr[j] : X.indptr[j + 1]]
        if len(cols) < 2:
            continue

        # Hold out a card, biased toward rarer (non-staple) cards.
        p = rarity[cols]
        p = p / p.sum() if p.sum() > 0 else None
        held = rng.choice(len(cols), p=p)
        target = cols[held]

        keep = np.delete(np.arange(len(cols)), held)
        weights = {
            int(c): float(fusion.quantity_transform([q], qmode)[0] * rarity[c])
            for c, q in zip(cols[keep], qty[keep])
        }
        query = fusion.pool_one(card_matrix, weights)
        if query is None:
            continue
        query = query / max(np.linalg.norm(query), 1e-12)

        scores = norm @ query
        scores[cols[keep]] = -np.inf  # already-present cards aren't candidates
        rank = 1 + int(np.sum(scores > scores[target]))
        ranks.append(rank)

    if not ranks:
        return {"mrr": 0.0, "n": 0}
    ranks = np.asarray(ranks)
    out = {"mrr": float(np.mean(1.0 / ranks)), "n": int(len(ranks))}
    for k in ks:
        out[f"hit@{k}"] = float(np.mean(ranks <= k))
    return out


def _l2(mat):
    mat = np.asarray(mat, dtype=np.float64)
    return mat / np.maximum(np.linalg.norm(mat, axis=1, keepdims=True), 1e-12)
