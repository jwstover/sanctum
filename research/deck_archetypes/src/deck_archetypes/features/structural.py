"""Deck-level STRUCTURAL summary — Channel 2 of the deck vector.

Captures a deck's *statistical shape* — the signal mean-pooling card embeddings
throws away. "Cheap allies", "low-cost event tempo", and "few splashy
high-cost finishers" are properties of the whole deck's distribution, not of any
single card.

Everything is computed with matrix algebra over the deck×card count matrix `X`:
a per-card indicator `M` [n_cards, n_feat] gives per-deck counts as `X @ M`.
Hand-designed and interpretable on purpose — clusters get named by hand, and
readable features are what make "why did this cluster form" answerable.

Toggles come from `deck_vector.structural.features` in the config.
"""

from __future__ import annotations

import numpy as np

from ..config import get


def build(corpus, cfg):
    """Return (matrix [n_decks, n_structural_features], feature_names)."""
    feats = get(cfg, "deck_vector.structural.features")
    normalize = get(cfg, "deck_vector.structural.normalize", "both")
    edges = corpus.cost_bucket_edges

    X = corpus.X
    B = corpus.binary()
    size = np.asarray(X.sum(axis=1)).ravel()
    size_safe = np.maximum(size, 1.0)

    cards = corpus.cards
    types = cards["type"].to_list()
    buckets = np.asarray(cards["cost_bucket"].to_list(), dtype=np.int64)
    cost = _num(cards["cost"].to_list())
    atk = _num(cards["atk"].to_list())
    thw = _num(cards["thw"].to_list())

    type_vocab = sorted({t for t in types if t is not None})
    n_buckets = len(edges)

    blocks, names = [], []

    def emit_distribution(counts, base_names):
        # Size-dependent group: fractions are the natural form; honor `normalize`.
        if normalize in ("fractions", "both"):
            blocks.append(counts / size_safe[:, None])
            names.extend(f"{n}#frac" for n in base_names)
        if normalize in ("counts", "both"):
            blocks.append(counts)
            names.extend(f"{n}#cnt" for n in base_names)

    def onehot(sel):
        return np.array([[1.0 if sel(t, b) else 0.0] for t, b in zip(types, buckets)]).reshape(
            len(types), 1
        )

    # --- cost × type crosstab (the discriminative one) ---
    if _on(feats, "cost_by_type_crosstab"):
        cols, cnames = [], []
        for b in range(n_buckets):
            for t in type_vocab:
                ind = np.array(
                    [1.0 if (tt == t and bb == b) else 0.0 for tt, bb in zip(types, buckets)]
                )
                cols.append(ind)
                cnames.append(f"cxt[b{b}|{t}]")
        M = np.vstack(cols).T  # [n_cards, B*T]
        emit_distribution(_mm(X, M), cnames)

    # --- type mix ---
    type_counts = None
    if _on(feats, "type_mix") or _needs_type_entropy(feats):
        M, cnames = _onehot_matrix(types, type_vocab, "type")
        type_counts = _mm(X, M)
        if _on(feats, "type_mix"):
            emit_distribution(type_counts, cnames)

    # --- trait distribution ---
    if _on(feats, "trait_distribution"):
        M, cnames = _multihot_matrix(cards["traits"].to_list(), "trait")
        emit_distribution(_mm(X, M), cnames)

    # --- flat cost curve ---
    bucket_counts = None
    if _on(feats, "cost_curve") or _needs_gini(feats):
        M, cnames = _onehot_matrix(
            [int(b) for b in buckets], list(range(n_buckets)), "costb"
        )
        bucket_counts = _mm(X, M)
        if _on(feats, "cost_curve"):
            emit_distribution(bucket_counts, cnames)

    # --- concentration / splashiness (scale-free; emitted as-is) ---
    conc = _get(feats, "concentration")
    if conc is not None:
        mean_cost = _mm(X, cost[:, None]).ravel() / size_safe
        if _on(conc, "cost_variance"):
            ex2 = _mm(X, (cost**2)[:, None]).ravel() / size_safe
            blocks.append((ex2 - mean_cost**2).reshape(-1, 1))
            names.append("cost_variance")
        if _on(conc, "cost_gini"):
            blocks.append(_cost_gini(bucket_counts, edges).reshape(-1, 1))
            names.append("cost_gini")
        if _on(conc, "high_cost_count"):
            mask = (cost >= 4).astype(np.float64)
            blocks.append(_mm(B, mask[:, None]))  # distinct 4+ cost cards
            names.append("high_cost_count")
        if _on(conc, "type_entropy"):
            p = type_counts / size_safe[:, None]
            ent = -(np.where(p > 0, p * np.log(p + 1e-12), 0.0)).sum(axis=1)
            blocks.append(ent.reshape(-1, 1))
            names.append("type_entropy")

    # --- ally stat-efficiency ---
    eff = _get(feats, "ally_efficiency")
    if eff is not None:
        ally = np.array([1.0 if t == "ally" else 0.0 for t in types])
        cost_tot = _mm(X, (cost * ally)[:, None]).ravel()
        cost_tot = np.maximum(cost_tot, 1.0)
        if _on(eff, "atk_per_cost"):
            blocks.append((_mm(X, (atk * ally)[:, None]).ravel() / cost_tot).reshape(-1, 1))
            names.append("ally_atk_per_cost")
        if _on(eff, "thw_per_cost"):
            blocks.append((_mm(X, (thw * ally)[:, None]).ravel() / cost_tot).reshape(-1, 1))
            names.append("ally_thw_per_cost")

    # --- resource profile ---
    if _on(feats, "resource_profile"):
        res = np.column_stack(
            [
                _num(cards[c].to_list())
                for c in (
                    "resource_physical",
                    "resource_mental",
                    "resource_energy",
                    "resource_wild",
                )
            ]
        )
        emit_distribution(_mm(X, res), ["res_phys", "res_mental", "res_energy", "res_wild"])

    # --- raw counts ---
    counts_cfg = _get(feats, "counts")
    if counts_cfg is not None:
        specs = {
            "n_allies": np.array([1.0 if t == "ally" else 0.0 for t in types]),
            "n_events": np.array([1.0 if t == "event" else 0.0 for t in types]),
            "n_upgrades_supports": np.array(
                [1.0 if t in ("upgrade", "support") else 0.0 for t in types]
            ),
            "n_cheap_0_1": (cost <= 1).astype(np.float64),
            "n_expensive_4plus": (cost >= 4).astype(np.float64),
        }
        for key, mask in specs.items():
            if _on(counts_cfg, key):
                counts = _mm(X, mask[:, None])
                if normalize in ("counts", "both"):
                    blocks.append(counts)
                    names.append(f"{key}#cnt")
                if normalize in ("fractions", "both"):
                    blocks.append(counts / size_safe[:, None])
                    names.append(f"{key}#frac")

    if not blocks:
        return np.zeros((corpus.n_decks, 0)), []
    return np.hstack(blocks), names


# --- helpers -----------------------------------------------------------------
def _mm(sparse_mat, dense):
    return np.asarray(sparse_mat @ dense)


def _num(values):
    return np.array([0.0 if v is None else float(v) for v in values], dtype=np.float64)


def _on(node, attr):
    return bool(getattr(node, attr, False)) if node is not None else False


def _get(node, attr):
    return getattr(node, attr, None) if node is not None else None


def _needs_type_entropy(feats):
    conc = _get(feats, "concentration")
    return _on(conc, "type_entropy")


def _needs_gini(feats):
    conc = _get(feats, "concentration")
    return _on(conc, "cost_gini")


def _onehot_matrix(values, vocab, prefix):
    idx = {v: i for i, v in enumerate(vocab)}
    m = np.zeros((len(values), len(vocab)))
    for r, v in enumerate(values):
        if v in idx:
            m[r, idx[v]] = 1.0
    return m, [f"{prefix}={v}" for v in vocab]


def _multihot_matrix(list_values, prefix):
    vocab = sorted({t for lst in list_values for t in (lst or [])})
    idx = {t: i for i, t in enumerate(vocab)}
    m = np.zeros((len(list_values), len(vocab)))
    for r, lst in enumerate(list_values):
        for t in lst or []:
            m[r, idx[t]] = 1.0
    return m, [f"{prefix}={t}" for t in vocab]


def _cost_gini(bucket_counts, edges):
    """Gini of the per-deck cost distribution, computed over cost buckets
    (representative cost = the bucket's lower edge). Vectorized across decks."""
    v = np.asarray(edges, dtype=np.float64)
    diff = np.abs(v[:, None] - v[None, :])  # [B, B]
    n = bucket_counts.sum(axis=1)
    n_safe = np.maximum(n, 1.0)
    mean = (bucket_counts @ v) / n_safe
    mad = np.einsum("di,ij,dj->d", bucket_counts, diff, bucket_counts) / (n_safe**2)
    mean_safe = np.where(mean > 0, mean, 1.0)
    return np.where(mean > 0, mad / (2 * mean_safe), 0.0)
