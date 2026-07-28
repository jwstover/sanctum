"""Swappable clusterers.

A Clusterer takes deck vectors [n_decks, dim] and returns labels [n_decks].
`-1` is reserved for noise (hdbscan) — archetype-less decks are a valid, wanted
outcome, so downstream code must tolerate a noise label. Soft methods
(nmf_topics) additionally expose `memberships` [n_decks, k].
"""

from __future__ import annotations

from typing import Protocol

import numpy as np


class Clusterer(Protocol):
    def fit_predict(self, deck_vectors: np.ndarray, cfg) -> np.ndarray:
        """Return integer labels; -1 == noise/archetype-less."""
        ...

    # Optional; only soft methods implement it.
    def memberships(self) -> "np.ndarray | None":
        ...


CLUSTERERS: dict[str, object] = {
    # "hdbscan": HdbscanClusterer,
    # "louvain": LouvainClusterer,      # builds a knn graph, community-detects
    # "kmeans": KmeansClusterer,
    # "nmf_topics": NmfTopics,          # soft: deck = mixture of archetypes
}


def build(method: str, cfg):
    if method not in CLUSTERERS:
        raise KeyError(f"unknown clustering method {method!r}; have {list(CLUSTERERS)}")
    return CLUSTERERS[method](cfg)
