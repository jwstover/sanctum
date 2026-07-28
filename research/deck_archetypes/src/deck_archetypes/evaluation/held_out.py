"""Held-out card prediction — the PRIMARY, label-free fitness metric.

The "language-model perplexity" of this problem. Hold one card out of each of a
sample of decks; ask the representation to rank the missing card among all
candidates. A representation that captured real deckbuilding structure ranks it
high. Needs ZERO human labels, so it's what you tune weights/channels against.

This is deliberately representation-level (not clustering-level): it scores the
deck/card vector space itself, before any clustering choice muddies things. If
fancy embeddings can't beat bag-of-cards + TF-IDF cosine here, that's the
answer — which is why the dumb baselines stay on the leaderboard.
"""

from __future__ import annotations


def evaluate(card_vectors, deck_card_rows, pooling_cfg, *, n_decks: int, ks, seed: int):
    """Return {"mrr": float, "hit@1": ..., "hit@5": ..., ...}.

    Procedure per sampled deck:
      1. Remove one held-out card (weight the sampling toward non-staples so the
         metric rewards capturing real structure, not re-predicting resources).
      2. Pool the REMAINING cards into a query deck vector (same pooling the
         pipeline uses).
      3. Score every candidate card (nearest-neighbor / dot-product in card
         space, or the backbone's own scorer) and find the held-out card's rank.
      4. Accumulate reciprocal rank and hit@k over the sample.

    Keep the sample + held-out choices seeded so runs are comparable on the
    leaderboard. Report per-k hit rates and MRR.
    """
    raise NotImplementedError
