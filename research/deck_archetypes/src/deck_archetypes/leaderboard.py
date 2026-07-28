"""Append one experiment's headline metrics to a parquet leaderboard.

Keyed by (snapshot_hash, config_hash) so re-running the same recipe overwrites
rather than duplicates, and only comparable runs sit side by side.
"""

from __future__ import annotations

from pathlib import Path

import polars as pl


def append(path, snapshot_hash, cfg, metrics):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)

    row = {
        "name": _g(cfg, "experiment.name"),
        "config_hash": cfg._hash,
        "snapshot_hash": snapshot_hash,
        "clustering": _g(cfg, "clustering.method"),
        "n_clusters": _dig(metrics, "intrinsic", "n_clusters"),
        "noise_fraction": _dig(metrics, "intrinsic", "noise_fraction"),
        "silhouette": _dig(metrics, "intrinsic", "silhouette"),
        "held_out_mrr": _dig(metrics, "held_out", "mrr"),
        "held_out_hit@10": _dig(metrics, "held_out", "hit@10"),
        "anchor_card_p": _anchor(metrics, "card_precision@"),
        "anchor_deck_p": _anchor(metrics, "deck_precision@"),
    }
    new = pl.DataFrame([row])

    if path.exists():
        old = pl.read_parquet(path)
        old = old.filter(
            ~(
                (pl.col("config_hash") == row["config_hash"])
                & (pl.col("snapshot_hash") == row["snapshot_hash"])
            )
        )
        new = pl.concat([old, new], how="diagonal_relaxed")
    new.write_parquet(path)
    return path


def _g(cfg, dotted):
    from .config import get

    return get(cfg, dotted)


def _dig(metrics, group, key):
    return (metrics.get(group) or {}).get(key)


def _anchor(metrics, prefix):
    a = metrics.get("anchors") or {}
    for k, v in a.items():
        if k.startswith(prefix):
            return v
    return None
