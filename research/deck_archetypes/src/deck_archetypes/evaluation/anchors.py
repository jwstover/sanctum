"""Anchor retrieval — the secondary, label-light metric.

Scores a representation against a small hand-seeded gold set
(anchors/archetypes.yaml). Two probes:
  - card-level: for each archetype's core cards, are their nearest cards the
    OTHER core cards of the same archetype? (precision@k)
  - deck-level: for each anchor deck, are its nearest decks other anchor decks
    of the same archetype? (precision@k)

Missing names/ids are skipped with a count so a half-filled anchor file still
scores what it can.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import yaml

from ..config import get


def evaluate(card_matrix, deck_vectors, corpus, cfg, *, base_dir="."):
    rel = get(cfg, "evaluation.anchor_retrieval.anchors_file", "anchors/archetypes.yaml")
    k = int(get(cfg, "evaluation.anchor_retrieval.k", 10))
    path = Path(base_dir) / rel
    if not path.exists():
        return {"status": "no_anchors_file", "path": str(path)}

    spec = yaml.safe_load(path.read_text()) or {}
    archetypes = spec.get("archetypes", [])

    name_to_col = _name_to_col(corpus)
    out = {"status": "ok"}
    card_p = _card_level(archetypes, name_to_col, card_matrix, k, out)
    deck_p = _deck_level(archetypes, corpus, deck_vectors, k, out)

    if card_p is not None:
        out[f"card_precision@{k}"] = card_p
    if deck_p is not None:
        out[f"deck_precision@{k}"] = deck_p
    return out


def _card_level(archetypes, name_to_col, card_matrix, k, out):
    norm = _l2(card_matrix)
    labelsets = {}
    resolved = 0
    unresolved = 0
    for arch in archetypes:
        cols = []
        for name in arch.get("core_cards") or []:
            col = name_to_col.get(name)
            if col is None:
                unresolved += 1
            else:
                cols.append(col)
                resolved += 1
        if len(cols) >= 2:
            labelsets[arch["label"]] = set(cols)

    out["anchor_cards_resolved"] = resolved
    out["anchor_cards_unresolved"] = unresolved
    if not labelsets:
        return None

    precisions = []
    for cols in labelsets.values():
        same = set(cols)
        for c in cols:
            sims = norm @ norm[c]
            sims[c] = -np.inf
            top = np.argpartition(-sims, k)[:k]
            hits = sum(1 for t in top if t in same)
            precisions.append(hits / k)
    return float(np.mean(precisions)) if precisions else None


def _deck_level(archetypes, corpus, deck_vectors, k, out):
    labeled = {}  # deck_row -> label
    for arch in archetypes:
        for did in arch.get("decks") or []:
            row = corpus.deck_index.get(did)
            if row is not None:
                labeled[row] = arch["label"]

    out["anchor_decks_resolved"] = len(labeled)
    if len(labeled) < 2:
        return None

    rows = np.array(list(labeled.keys()))
    sub = _l2(deck_vectors[rows])
    labels = np.array([labeled[r] for r in rows])
    precisions = []
    for i in range(len(rows)):
        sims = sub @ sub[i]
        sims[i] = -np.inf
        kk = min(k, len(rows) - 1)
        top = np.argpartition(-sims, kk - 1)[:kk]
        hits = int(np.sum(labels[top] == labels[i]))
        precisions.append(hits / kk)
    return float(np.mean(precisions))


def _name_to_col(corpus):
    names = corpus.cards["name"].to_list()
    ids = corpus.cards["card_id"].to_list()
    return {name: corpus.card_index[cid] for name, cid in zip(names, ids)}


def _l2(mat):
    mat = np.asarray(mat, dtype=np.float64)
    return mat / np.maximum(np.linalg.norm(mat, axis=1, keepdims=True), 1e-12)
