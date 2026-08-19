"""Cluster interpretation — the human-facing output that turns cluster ids into
nameable archetypes.

For each cluster: the top cards by LIFT (P(card | cluster) / P(card | corpus)) —
the cards that are disproportionately characteristic, which usually name the
archetype themselves ("Firepower, Combat Training, Boot Camp, ...") — plus a few
representative deck links (the decks closest to the cluster centroid) so you can
open real examples. Writes a readable text report and returns a compact summary.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from ..config import get


def report(corpus, labels, cfg, out_dir, deck_space=None):
    top_n = int(get(cfg, "evaluation.interpret.top_cards_per_cluster", 25))
    n_samples = int(get(cfg, "evaluation.interpret.sample_decks", 5))
    url_base = get(cfg, "evaluation.interpret.deck_url_base", "http://localhost:4150/decks/")
    labels = np.asarray(labels)
    names = corpus.cards["name"].to_list()

    B = corpus.binary()
    global_p = np.asarray(B.mean(axis=0)).ravel()  # P(card in a deck)

    clusters = sorted(c for c in set(labels.tolist()) if c != -1)
    lines, summary = [], []

    lines.append(f"# Cluster report — {len(clusters)} clusters "
                 f"({int(np.sum(labels == -1))} decks noise)\n")

    for c in clusters:
        rows = np.where(labels == c)[0]
        sub = B[rows]
        cluster_p = np.asarray(sub.mean(axis=0)).ravel()
        lift = cluster_p / np.maximum(global_p, 1e-9)
        # Rank by lift, but require the card to actually appear in the cluster.
        lift[cluster_p < 0.05] = 0.0
        top = np.argsort(-lift)[:top_n]
        top_cards = [(names[i], round(float(lift[i]), 1), round(float(cluster_p[i]), 2)) for i in top]

        samples = _representative_decks(rows, deck_space, corpus, url_base, n_samples)

        summary.append(
            {
                "cluster": int(c),
                "size": int(len(rows)),
                "top_cards": top_cards[:8],
                "sample_decks": samples,
            }
        )

        lines.append(f"\n## Cluster {c}  ({len(rows)} decks)")
        for name, lf, pr in top_cards:
            lines.append(f"  {lf:5.1f}×  {pr:4.0%}  {name}")
        if samples:
            lines.append("  sample decks (nearest the cluster centroid):")
            for url in samples:
                lines.append(f"    {url}")

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "clusters.txt").write_text("\n".join(lines))
    return {"n_clusters": len(clusters), "clusters": summary}


def _representative_decks(rows, deck_space, corpus, url_base, n):
    """The n decks closest to the cluster centroid — the most typical examples."""
    if deck_space is None or n <= 0 or len(rows) == 0:
        return []
    sub = deck_space[rows]
    centroid = sub.mean(axis=0)
    order = np.argsort(np.linalg.norm(sub - centroid, axis=1))[:n]
    return [f"{url_base}{corpus.deck_ids[rows[i]]}" for i in order]
