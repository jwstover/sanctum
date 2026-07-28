"""Swappable representation backbones.

A Representation turns the corpus into card vectors (Channel A: distributional).
Channels B (text) and C (card_features) are built separately in features/ and
then merged with A by fusion.py — so a backbone here only owns co-occurrence.

Register concrete backbones (ppmi_svd, word2vec, nmf) under BACKBONES so the
pipeline can select one by `representation.distributional.method`.
"""

from __future__ import annotations

from typing import Protocol


class Representation(Protocol):
    """Co-occurrence backbone. `fit` sees the deck→cards corpus; `card_vectors`
    returns a dict {card_id: vector} for the filtered vocabulary."""

    def fit(self, deck_card_rows, cfg) -> "Representation": ...

    def card_vectors(self) -> dict: ...


# name -> factory(cfg) -> Representation
BACKBONES: dict[str, object] = {
    # "ppmi_svd": PpmiSvd,
    # "word2vec": Word2Vec,
    # "nmf": Nmf,
}


def build(method: str, cfg):
    if method == "none":
        return None
    if method not in BACKBONES:
        raise KeyError(f"unknown distributional method {method!r}; have {list(BACKBONES)}")
    return BACKBONES[method](cfg)
