"""Report for NMF soft-membership runs.

Writes, per topic: its defining cards (top H weights), how many decks have it as
their dominant topic, and representative decks (highest loading). If an anchor
file is present, also reports each anchor label's MEAN loading across topics and
its single dominant topic — the direct test of "does a firepower topic exist and
do the firepower anchor decks load on it?"
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import yaml

from ..config import get
from ..representation import nmf_topics


def report(corpus, result, cfg, out_dir, base_dir="."):
    W = result.memberships  # [n_decks, k] mixtures
    H = result.components  # [k, n_cards]
    k = H.shape[0]
    url_base = get(cfg, "evaluation.interpret.deck_url_base", "http://localhost:4150/decks/")
    n_samples = int(get(cfg, "evaluation.interpret.sample_decks", 5))

    lines = [f"# NMF topics — {k} topics over {corpus.n_decks} decks\n"]
    for t in range(k):
        dominant = int(np.sum(result.labels == t))
        cards = nmf_topics.top_cards(H[t], corpus, n=12)
        top = np.argsort(-W[:, t])[:n_samples]
        lines.append(f"\n## Topic {t}  (dominant for {dominant} decks)")
        lines.append("  cards: " + ", ".join(f"{n}" for n, _ in cards))
        lines.append("  top-loading decks:")
        for i in top:
            lines.append(f"    {W[i, t]:.2f}  {url_base}{corpus.deck_ids[i]}")

    anchors = _anchor_loadings(corpus, W, cfg, base_dir)
    if anchors:
        lines.append("\n\n# Anchor label → topic loadings")
        for label, info in anchors.items():
            lines.append(
                f"\n## {label}  ({info['n']} decks)  dominant topic = {info['dominant']}"
            )
            for t, val in info["top_topics"]:
                cards = ", ".join(n for n, _ in nmf_topics.top_cards(H[t], corpus, n=6))
                lines.append(f"    topic {t:2}  mean load {val:.3f}   [{cards}]")

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "topics.txt").write_text("\n".join(lines))
    return {"n_topics": k, "anchors": anchors}


def _anchor_loadings(corpus, W, cfg, base_dir):
    rel = get(cfg, "evaluation.anchor_retrieval.anchors_file", "anchors/archetypes.yaml")
    path = Path(base_dir) / rel
    if not path.exists():
        return {}
    spec = yaml.safe_load(path.read_text()) or {}

    out = {}
    for arch in spec.get("archetypes", []):
        rows = [corpus.deck_index[d] for d in (arch.get("decks") or []) if d in corpus.deck_index]
        if not rows:
            continue
        mean_load = W[rows].mean(axis=0)
        order = np.argsort(-mean_load)[:3]
        out[arch["label"]] = {
            "n": len(rows),
            "dominant": int(mean_load.argmax()),
            "top_topics": [(int(t), float(mean_load[t])) for t in order],
        }
    return out
