"""Clustering stage. `-1` is reserved for noise (HDBSCAN) — archetype-less decks
are a valid, wanted outcome, so downstream code tolerates a noise label.

Backed by scikit-learn (its HDBSCAN lands in 1.3+), so no fragile native deps.
Optional pre-cluster dimensionality reduction (PCA always available; UMAP used
when installed).
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from ..config import get


@dataclass
class ClusterResult:
    labels: np.ndarray
    memberships: np.ndarray | None
    reduced: np.ndarray
    method: str


def cluster(deck_vectors: np.ndarray, cfg) -> ClusterResult:
    method = get(cfg, "clustering.method", "hdbscan")
    reduced = _reduce(deck_vectors, cfg)

    if method == "hdbscan":
        labels, memberships = _hdbscan(reduced, cfg)
    elif method == "kmeans":
        labels, memberships = _kmeans(reduced, cfg)
    elif method == "agglomerative":
        labels, memberships = _agglomerative(reduced, cfg)
    else:
        raise ValueError(f"unsupported clustering.method {method!r} (spine: hdbscan|kmeans|agglomerative)")

    return ClusterResult(labels=labels, memberships=memberships, reduced=reduced, method=method)


def _reduce(deck_vectors, cfg):
    spec = get(cfg, "clustering.reduce")
    method = getattr(spec, "method", "none") if spec is not None else "none"
    dim = int(getattr(spec, "dim", 15)) if spec is not None else 15
    if method in ("none", None) or dim >= deck_vectors.shape[1]:
        return deck_vectors
    if method == "umap":
        try:
            import umap

            return umap.UMAP(n_components=dim, random_state=0).fit_transform(deck_vectors)
        except ImportError:
            pass  # fall through to PCA
    from sklearn.decomposition import PCA

    return PCA(n_components=dim, random_state=0).fit_transform(deck_vectors)


def _hdbscan(x, cfg):
    from sklearn.cluster import HDBSCAN

    model = HDBSCAN(
        min_cluster_size=int(get(cfg, "clustering.hdbscan.min_cluster_size", 50)),
        min_samples=int(get(cfg, "clustering.hdbscan.min_samples", 10)),
        metric=get(cfg, "clustering.hdbscan.metric", "euclidean"),
        copy=True,
    )
    labels = model.fit_predict(x)
    return labels, None


def _kmeans(x, cfg):
    from sklearn.cluster import KMeans

    k = int(get(cfg, "clustering.kmeans.k", 20))
    model = KMeans(n_clusters=k, random_state=0, n_init=10)
    labels = model.fit_predict(x)
    return labels, None


def _agglomerative(x, cfg):
    from sklearn.cluster import AgglomerativeClustering

    k = int(get(cfg, "clustering.agglomerative.k", 20))
    labels = AgglomerativeClustering(n_clusters=k).fit_predict(x)
    return labels, None
