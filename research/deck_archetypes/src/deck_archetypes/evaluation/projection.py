"""Optional 2D projection of the deck space for eyeballing clusters.

Guarded: needs matplotlib (and uses UMAP when installed, else PCA). Silently
skips if matplotlib is absent so a headless run still completes.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from ..config import get


def render(deck_vectors, labels, cfg, out_dir):
    if not get(cfg, "evaluation.projection.umap_2d", False):
        return {"status": "disabled"}
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        return {"status": "skipped_no_matplotlib"}

    xy = _project_2d(deck_vectors)
    labels = np.asarray(labels)
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    fig, ax = plt.subplots(figsize=(9, 9), dpi=110)
    noise = labels == -1
    ax.scatter(xy[noise, 0], xy[noise, 1], s=2, c="#cccccc", alpha=0.4, label="noise")
    for c in sorted(set(labels[~noise].tolist())):
        m = labels == c
        ax.scatter(xy[m, 0], xy[m, 1], s=4, alpha=0.7)
    ax.set_title("Deck space (2D projection)")
    ax.set_xticks([])
    ax.set_yticks([])
    fig.savefig(out_dir / "projection.png", bbox_inches="tight")
    plt.close(fig)
    return {"status": "ok", "path": str(out_dir / "projection.png")}


def _project_2d(deck_vectors):
    try:
        import umap

        return umap.UMAP(n_components=2, random_state=0).fit_transform(deck_vectors)
    except ImportError:
        from sklearn.decomposition import PCA

        return PCA(n_components=2, random_state=0).fit_transform(deck_vectors)
