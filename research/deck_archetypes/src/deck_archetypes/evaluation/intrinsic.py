"""Intrinsic (label-free) clustering quality — silhouette, Davies-Bouldin,
cluster count, and noise fraction. All computed on the clustered (reduced) space
with the noise label excluded.
"""

from __future__ import annotations

import numpy as np

from ..config import get


def evaluate(reduced, labels, cfg, *, seed=42):
    intr = get(cfg, "evaluation.intrinsic")
    labels = np.asarray(labels)
    mask = labels != -1
    uniq = sorted(set(labels[mask].tolist()))

    out = {
        "n_clusters": len(uniq),
        "noise_fraction": float(np.mean(labels == -1)),
        "clustered_fraction": float(np.mean(mask)),
    }
    if len(uniq) < 2 or mask.sum() < len(uniq) + 1:
        return out  # metrics undefined with <2 clusters

    x = reduced[mask]
    y = labels[mask]

    if _on(intr, "silhouette"):
        from sklearn.metrics import silhouette_score

        rng = np.random.default_rng(seed)
        sample = min(5000, x.shape[0])
        sel = rng.choice(x.shape[0], size=sample, replace=False)
        out["silhouette"] = float(silhouette_score(x[sel], y[sel]))

    if _on(intr, "davies_bouldin"):
        from sklearn.metrics import davies_bouldin_score

        out["davies_bouldin"] = float(davies_bouldin_score(x, y))

    return out


def _on(node, attr):
    return bool(getattr(node, attr, False)) if node is not None else False
