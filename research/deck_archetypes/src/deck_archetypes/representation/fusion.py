"""Assemble card vectors from channels, pool them into deck vectors, and combine
the pooled-embedding channel with the structural channel.

Three fusion points, each with its own normalize + weight knobs:
  1. fuse_card_channels — distributional ⊕ text ⊕ card_features → one card vector
  2. pool               — weighted mean of card vectors → deck embedding channel
  3. combine_deck_channels — [pooled embedding, structural] → final deck vector
"""

from __future__ import annotations

import numpy as np
from scipy import sparse

from ..config import get


# --- 1. per-card channel fusion ---------------------------------------------
def fuse_card_channels(channels: dict, cfg):
    """channels: {name: matrix [n_cards, d]}. Returns fused [n_cards, D]."""
    norm = get(cfg, "representation.card_fusion.normalize_per_channel", "l2")
    weights = get(cfg, "representation.card_fusion.weights")
    parts = []
    for name, mat in channels.items():
        if mat is None or mat.shape[1] == 0:
            continue
        w = float(getattr(weights, name, 1.0)) if weights is not None else 1.0
        parts.append(_normalize(mat, norm) * w)
    if not parts:
        raise ValueError("no card channels enabled")
    return np.hstack(parts)


# --- 2. pool card vectors into a deck embedding ------------------------------
def pool(card_matrix, corpus, cfg):
    """Weighted mean of a deck's card vectors. Returns [n_decks, D]."""
    quantity_weight = get(cfg, "deck_vector.pooling.quantity_weight", "sqrt")
    rarity_weight = get(cfg, "deck_vector.pooling.rarity_weight", "tfidf")

    W = _pool_weights(corpus, quantity_weight, rarity_weight)  # sparse [n_decks, n_cards]
    num = np.asarray(W @ card_matrix)
    denom = np.asarray(W.sum(axis=1)).ravel()
    denom = np.maximum(denom, 1e-9)
    return num / denom[:, None]


def pool_one(card_matrix, card_weights):
    """Pool a single deck given {col_index: weight}. Used by held-out eval."""
    if not card_weights:
        return None
    idx = np.fromiter(card_weights.keys(), dtype=np.int64)
    w = np.fromiter(card_weights.values(), dtype=np.float64)
    vec = (card_matrix[idx] * w[:, None]).sum(axis=0) / max(w.sum(), 1e-9)
    return vec


def pool_weight_vector(corpus, cfg):
    """Per-card pooling weight (rarity × aspect_downweight) as a dense vector —
    lets held-out eval reconstruct per-deck weights consistently with `pool`."""
    rarity_weight = get(cfg, "deck_vector.pooling.rarity_weight", "tfidf")
    base = corpus.idf if rarity_weight == "tfidf" else np.ones(corpus.n_cards)
    return base * corpus.card_weight


def quantity_transform(values, mode):
    values = np.asarray(values, dtype=np.float64)
    if mode == "binary":
        return (values > 0).astype(np.float64)
    if mode == "sqrt":
        return np.sqrt(values)
    return values  # linear


# --- 3. combine the two deck channels ----------------------------------------
def combine_deck_channels(named_channels: dict, cfg):
    """named_channels: {'embedding': mat, 'structural': mat}. Returns final vec."""
    per = get(cfg, "deck_vector.channels.normalize_per_channel", "zscore")
    weights = get(cfg, "deck_vector.channels.weights")
    final = get(cfg, "deck_vector.channels.final_normalize", "l2")

    parts = []
    for name, mat in named_channels.items():
        if mat is None or mat.shape[1] == 0:
            continue
        w = float(getattr(weights, name, 1.0)) if weights is not None else 1.0
        parts.append(_normalize(mat, per) * w)
    combined = np.hstack(parts)
    return _normalize(combined, final)


# --- internals ---------------------------------------------------------------
def _pool_weights(corpus, quantity_weight, rarity_weight):
    X = corpus.X.tocoo()
    q = quantity_transform(X.data, quantity_weight)
    base = corpus.idf if rarity_weight == "tfidf" else np.ones(corpus.n_cards)
    q = q * (base * corpus.card_weight)[X.col]  # rarity × aspect_downweight
    return sparse.csr_matrix((q, (X.row, X.col)), shape=X.shape)


def _normalize(mat, mode):
    mat = np.asarray(mat, dtype=np.float64)
    if mode == "l2":
        norms = np.linalg.norm(mat, axis=1, keepdims=True)
        return mat / np.maximum(norms, 1e-12)
    if mode == "zscore":
        mu = mat.mean(axis=0, keepdims=True)
        sd = mat.std(axis=0, keepdims=True)
        return (mat - mu) / np.maximum(sd, 1e-12)
    return mat
