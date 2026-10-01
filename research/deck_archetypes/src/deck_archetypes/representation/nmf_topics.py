"""NMF soft-membership over the deck×card matrix — archetypes as topics.

Factorizes the (IDF-weighted) deck×card counts A ≈ W·H:
  - W [n_decks, k]  — each deck's nonneg loading on each topic (a mixture).
  - H [k, n_cards]  — each topic's card weights (its defining cards).

Unlike hard clustering, a deck can be "55% S.H.I.E.L.D., 30% firepower" — the
right model for overlapping *package* archetypes like firepower, which co-occur
with a hero's other choices rather than defining a whole-deck family.
"""

from __future__ import annotations

import numpy as np
from sklearn.decomposition import NMF

from ..config import get


def fit(corpus, cfg):
    """Return (W [n_decks, k], H [k, n_cards])."""
    k = int(get(cfg, "clustering.nmf_topics.k", 20))
    max_iter = int(get(cfg, "clustering.nmf_topics.max_iter", 400))

    # IDF × aspect-downweight column weighting, so staples don't dominate topics.
    weights = corpus.idf * corpus.card_weight
    a = corpus.X.multiply(weights.reshape(1, -1)).tocsr()
    a.data = np.maximum(a.data, 0.0)  # NMF requires nonnegative input

    model = NMF(n_components=k, init="nndsvda", random_state=0, max_iter=max_iter)
    w = model.fit_transform(a)
    h = model.components_
    return w, h


def top_cards(h_row, corpus, n=15):
    """Names of the top-weighted cards for one topic row of H."""
    names = corpus.cards["name"].to_list()
    idx = np.argsort(-h_row)[:n]
    return [(names[i], round(float(h_row[i]), 3)) for i in idx]
