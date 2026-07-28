"""Playstyle breakdown — per-deck star ratings on the dimensions MarvelCDB
writeups use (Damage / Threat Control / Survivability / Economy / Card Drawing,
plus Complexity).

Each card contributes to each dimension from its stats, traits, and a few text
keywords. A deck's raw score is the quantity-weighted sum of its cards; stars are
that score's quintile across the whole corpus (1★ = bottom 20%, 5★ = top 20%),
so ratings are relative to the real meta.

Heuristic and tunable — meant to reproduce the *shape* of a human writeup's
breakdown, not to be exact. Runs on a corpus built WITHOUT stripping hero cards
(a deck's signature cards shape its playstyle too).
"""

from __future__ import annotations

import numpy as np

DIMENSIONS = ["Damage", "Threat Control", "Survivability", "Economy", "Card Drawing", "Complexity"]


def _has(text, *subs):
    t = (text or "").lower()
    return 1.0 if any(s in t for s in subs) else 0.0


def card_contributions(corpus):
    """[n_cards, n_dims] contribution of each card to each dimension."""
    c = corpus.cards
    types = c["type"].to_list()
    traits = c["traits"].to_list()
    texts = c["text"].to_list()

    def num(col):
        return np.array([0.0 if v is None else float(v) for v in c[col].to_list()])

    atk, thw, dfn, hp = num("atk"), num("thw"), num("def"), num("hp")
    res = num("resource_physical") + num("resource_mental") + num("resource_energy") + num("resource_wild")

    n = c.height
    M = np.zeros((n, len(DIMENSIONS)))
    for i in range(n):
        txt = texts[i]
        weapon = 1.0 if "Weapon" in (traits[i] or []) else 0.0
        # Damage: ally ATK, "deal damage", ATK-boost upgrades ("[attack]"), weapons.
        M[i, 0] = atk[i] + 1.5 * _has(txt, "damage") + 1.2 * _has(txt, "[attack]", "attack (atk)") + weapon
        # Threat Control: ally THW, thwart/threat-removal, THW-boost upgrades.
        M[i, 1] = thw[i] + 1.5 * _has(txt, "thwart", "remove", "threat") + 1.0 * _has(txt, "[thwart]")
        # Survivability: DEF stat, ally soak, defense-boost + damage-prevention.
        M[i, 2] = (
            dfn[i]
            + 0.4 * hp[i]
            + 1.5 * _has(txt, "defense", "[defense]", "defend")
            + 1.2 * _has(txt, "prevent", "heal", "recover", "less damage", "reduce that damage", "tough")
        )
        # Economy: resource icons, cost reduction, resource generation.
        M[i, 3] = res[i] + 1.0 * _has(txt, "resource", "reduce the cost", "costs 1 less", "generate")
        # Card Drawing: explicit draw effects (not incidental "draw" mentions).
        M[i, 4] = 1.5 * _has(txt, "draw a card", "draw 1", "draw 2", "draw two", "draw three",
                             "draw cards", "draw an additional", "cards into your hand")
        # Complexity: advanced-timing / decision words (not the ubiquitous when/if).
        M[i, 5] = _has(txt, "response", "interrupt", "forced", "search your", "choose")
    return M


def deck_raw_scores(corpus):
    """[n_decks, n_dims] quantity-weighted sum of card contributions."""
    return np.asarray(corpus.X @ card_contributions(corpus))


def to_stars(raw):
    """Column-wise quintile → 1..5 stars, using percentile rank across decks."""
    n = raw.shape[0]
    order = raw.argsort(axis=0)
    rank = np.empty_like(raw)
    for j in range(raw.shape[1]):
        rank[order[:, j], j] = np.arange(n)
    pct = rank / max(n - 1, 1)
    return np.clip((pct * 5).astype(int) + 1, 1, 5)


def breakdown(corpus, deck_id, stars=None):
    """{dimension: n_stars} for one deck."""
    if stars is None:
        stars = to_stars(deck_raw_scores(corpus))
    row = corpus.deck_index.get(deck_id)
    if row is None:
        return None
    return {DIMENSIONS[j]: int(stars[row, j]) for j in range(len(DIMENSIONS))}


def render(bd):
    """Pretty star lines for a breakdown dict."""
    return "\n".join(f"  {d:16}{'★' * bd[d]}{'☆' * (5 - bd[d])}" for d in DIMENSIONS)
