"""Distributional backbone dispatch (Channel A: co-occurrence).

Channels B (text) and C (card_features) are built in features/ and merged with A
by fusion.fuse_card_channels — a backbone here only owns co-occurrence.
"""

from __future__ import annotations

import numpy as np

from ..config import get


def card_vectors(corpus, cfg):
    """Return (matrix [n_cards, dim], names) or (None, []) when disabled."""
    dist = get(cfg, "representation.distributional")
    if dist is None or not getattr(dist, "enabled", False):
        return None, []

    method = getattr(dist, "method", "ppmi_svd")
    if method == "ppmi_svd":
        from . import ppmi_svd

        return ppmi_svd.card_vectors(corpus, cfg)
    if method == "none":
        return None, []
    raise ValueError(
        f"distributional method {method!r} not in the spine (have: ppmi_svd; "
        "word2vec/nmf are future backbones)"
    )


def zeros(corpus, dim=1):
    return np.zeros((corpus.n_cards, dim))
