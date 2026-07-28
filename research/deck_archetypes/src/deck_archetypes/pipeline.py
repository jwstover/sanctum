"""Wire the stages from a config and run one experiment.

    from deck_archetypes.pipeline import run
    metrics = run("configs/baseline.yaml", snapshot_dir=..., base_dir=...)
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from . import leaderboard
from .clustering import base as clustering
from .config import get, load_config
from .evaluation import anchors, held_out, intrinsic, interpret, projection
from .features import card_features, structural, text_embed
from .preprocess import aspect_counts, build_corpus
from .representation import base as representation
from .representation import fusion
from .snapshot import load_snapshot


def run(config_path, *, snapshot_dir=None, base_dir="."):
    base = Path(base_dir)
    cfg = load_config(config_path)

    snapshot_dir = snapshot_dir or (base / "snapshots" / get(cfg, "experiment.snapshot"))
    snap = load_snapshot(snapshot_dir)

    if get(cfg, "corpus.partition_by") == "aspect":
        return _run_partitioned(cfg, snap, base)
    corpus = build_corpus(snap, cfg)
    return _run_single(cfg, snap, corpus, base, tag=None)


def _run_partitioned(cfg, snap, base):
    """Within-aspect clustering: one independent run per aspect. This is the
    default archetype finder — most heroes build a single aspect, so archetypes
    live inside one, and a global run mostly rediscovers the aspect partition."""
    min_decks = int(get(cfg, "corpus.partition_min_decks", 200))
    counts = aspect_counts(snap, cfg)
    aspects = sorted(a for a, n in counts.items() if n >= min_decks)
    _log(f"partition_by aspect: {aspects} "
         f"(skipped {sorted(a for a, n in counts.items() if n < min_decks)})")

    results = {}
    for asp in aspects:
        corpus = build_corpus(snap, cfg, restrict_aspects=[asp])
        _log(f"[{asp}] corpus: {corpus.n_decks} decks × {corpus.n_cards} cards")
        results[asp] = _run_single(cfg, snap, corpus, base, tag=asp)
    return results


def _run_single(cfg, snap, corpus, base, tag):
    _log(f"corpus: {corpus.n_decks} decks × {corpus.n_cards} cards "
         f"(snapshot {snap.hash}{'' if tag is None else f', aspect={tag}'})")

    # --- representation: fuse card channels -> pool -> combine with structural
    channels = {}
    dist, _ = representation.card_vectors(corpus, cfg)
    if dist is not None:
        channels["distributional"] = dist
    if get(cfg, "representation.text.enabled", False):
        channels["text"], _ = text_embed.build(corpus, cfg, cache_dir=base / "runs" / "cache")
    if get(cfg, "representation.card_features.enabled", False):
        channels["card_features"], _ = card_features.build(corpus, cfg)

    card_matrix = fusion.fuse_card_channels(channels, cfg)
    pooled = fusion.pool(card_matrix, corpus, cfg)
    _log(f"card space: {card_matrix.shape[1]}d  ·  deck embedding: {pooled.shape[1]}d")

    deck_channels = {"embedding": pooled}
    if get(cfg, "deck_vector.structural.enabled", False):
        struct, struct_names = structural.build(corpus, cfg)
        deck_channels["structural"] = struct
        _log(f"structural channel: {struct.shape[1]} features")

    deck_vectors = fusion.combine_deck_channels(deck_channels, cfg)

    # --- clustering
    result = clustering.cluster(deck_vectors, cfg)
    _log(f"clustering [{result.method}]: {_n_clusters(result.labels)} clusters, "
         f"{int(np.sum(result.labels == -1))} noise")

    # --- evaluation
    out_dir = base / _resolve(get(cfg, "output.dir", "runs/default"), cfg)
    if tag is not None:
        out_dir = out_dir / tag
    metrics = {}
    if get(cfg, "evaluation.held_out_prediction.enabled", False):
        metrics["held_out"] = held_out.evaluate(card_matrix, corpus, cfg)
    if get(cfg, "evaluation.anchor_retrieval.enabled", False):
        metrics["anchors"] = anchors.evaluate(card_matrix, deck_vectors, corpus, cfg, base_dir=base)
    metrics["intrinsic"] = intrinsic.evaluate(result.reduced, result.labels, cfg)
    metrics["interpret"] = interpret.report(
        corpus, result.labels, cfg, out_dir, deck_space=result.reduced
    )
    metrics["projection"] = projection.render(deck_vectors, result.labels, cfg, out_dir)

    _save_outputs(out_dir, cfg, corpus, card_matrix, deck_vectors, result, metrics)
    leaderboard.append(base / get(cfg, "output.leaderboard", "runs/leaderboard.parquet"),
                       snap.hash, cfg, metrics, partition=tag)
    _log(f"wrote {out_dir}")
    return metrics


def _save_outputs(out_dir, cfg, corpus, card_matrix, deck_vectors, result, metrics):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    save = set(getattr(get(cfg, "output"), "save", []) or [])
    if "card_vectors" in save:
        np.save(out_dir / "card_vectors.npy", card_matrix)
    if "deck_vectors" in save:
        np.save(out_dir / "deck_vectors.npy", deck_vectors)
    if "assignments" in save:
        np.save(out_dir / "assignments.npy", result.labels)
    (out_dir / "metrics.json").write_text(json.dumps(metrics, indent=2, default=str))


def _resolve(path, cfg):
    return path.replace("${experiment.name}", get(cfg, "experiment.name", "run"))


def _n_clusters(labels):
    return len({c for c in labels.tolist() if c != -1})


def _log(msg):
    print(f"[pipeline] {msg}", flush=True)
