"""Distributional backbone: shifted-PPMI over card co-occurrence + truncated SVD.

Per Levy & Goldberg, SVD of a shifted-PPMI matrix approximates skip-gram
word2vec. Deterministic and instant at this scale (a few thousand cards). The
"context" of a card is the other cards in the same deck.
"""

from __future__ import annotations

import numpy as np
from sklearn.decomposition import TruncatedSVD

from ..config import get


def card_vectors(corpus, cfg):
    """Return (matrix [n_cards, dim], feature_names) aligned to corpus.card_ids."""
    dim = int(get(cfg, "representation.distributional.dim", 64))
    shift_k = float(get(cfg, "representation.distributional.pmi_shift_k", 1))

    B = corpus.binary()
    cooc = np.asarray((B.T @ B).todense()).astype(np.float64)  # [n_cards, n_cards]
    np.fill_diagonal(cooc, 0.0)

    total = cooc.sum()
    if total == 0:
        return np.zeros((corpus.n_cards, dim)), [f"svd_{i}" for i in range(dim)]

    row = cooc.sum(axis=1, keepdims=True)
    col = cooc.sum(axis=0, keepdims=True)
    with np.errstate(divide="ignore", invalid="ignore"):
        pmi = np.log((cooc * total) / (row * col))
    ppmi = np.maximum(pmi - np.log(max(shift_k, 1e-9)), 0.0)
    ppmi[~np.isfinite(ppmi)] = 0.0

    dim = min(dim, max(1, min(ppmi.shape) - 1))
    svd = TruncatedSVD(n_components=dim, random_state=0)
    u = svd.fit_transform(ppmi)  # [n_cards, dim], already scaled by singular values
    return u, [f"svd_{i}" for i in range(u.shape[1])]
