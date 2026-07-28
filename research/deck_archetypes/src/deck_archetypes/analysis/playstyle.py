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

Calibrated against 96 MarvelCDB decks whose descriptions carry explicit star
ratings (see analysis/calibrate_playstyle.py). Findings baked in here:
  * scores are DENSITY (per-card averages), not raw sums — human ratings reflect
    a deck's focus, and raw totals saturate on big decks;
  * the Damage rule avoids the ubiquitous "damage" keyword (on nearly every
    card) in favor of explicit "deal N damage", ATK-boosts, and weapons;
  * a hero-identity term (base stats + hero/alter-ego ability) is added — the
    identity card isn't a deck slot, so it's otherwise invisible, yet it shapes
    playstyle a lot (it lifted Damage 0.21→0.33, Survivability 0.26→0.41).
Mean per-dimension Spearman vs the human ratings: 0.37 (Threat Control 0.57,
Survivability 0.41, Economy 0.34, Damage 0.33, Card Drawing 0.29, Complexity 0.27).
"""

from __future__ import annotations

import re

import numpy as np

# Damage scores best as per-card density; Complexity best as an absolute count.
_DENSITY_DIMS = {0, 1, 2, 3, 4}

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
        # Damage: ally ATK, explicit "deal N damage", ATK-boost upgrades, weapons.
        # The bare word "damage" is on nearly every card, so it's excluded — it
        # saturated the score (Spearman ~0 vs human ratings) until removed.
        deal_n = 1.0 if re.search(r"deal \d+ damage", (txt or "").lower()) else 0.0
        M[i, 0] = atk[i] + 2.0 * deal_n + 1.5 * _has(txt, "[attack]") + weapon
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


def hero_contributions(heroes):
    """{hero_id: [n_dims]} from the hero's base stats + hero/alter-ego ability
    text. These never appear in deck_cards (the identity card isn't a deck slot),
    so they'd otherwise be invisible to the scorer."""
    out = {}
    for row in heroes.iter_rows(named=True):
        n = lambda k: float(row.get(k) or 0)
        t = ((row.get("hero_text") or "") + " " + (row.get("ae_text") or "")).lower()
        hand = n("hero_hand_size")
        out[row["hero_id"]] = np.array([
            n("atk") + _has(t, "deal", "[attack]"),                                # Damage
            n("thw") + _has(t, "thwart", "[thwart]", "threat"),                    # Threat Control
            n("def") + 0.5 * n("recover") + _has(t, "prevent", "heal", "recover", "defense"),  # Survivability
            _has(t, "resource", "reduce the cost", "generate"),                    # Economy
            max(hand - 4, 0) * 0.5 + _has(t, "draw"),                              # Card Drawing
            _has(t, "response", "interrupt", "forced", "choose", "search"),        # Complexity
        ])
    return out


def deck_scores(corpus, heroes=None, hero_weight=0.1):
    """Calibrated per-deck scores: density (per-card) for most dimensions,
    absolute for Complexity, plus a hero-identity term (base stats + ability)
    when hero data is available. This is what stars are computed from."""
    raw = deck_raw_scores(corpus)
    size = np.asarray(corpus.X.sum(axis=1)).reshape(-1, 1)
    scores = raw.copy()
    dens_cols = sorted(_DENSITY_DIMS)
    scores[:, dens_cols] = raw[:, dens_cols] / np.maximum(size, 1e-9)

    if heroes is not None and hero_weight:
        contrib = hero_contributions(heroes)
        blank = np.zeros(len(DIMENSIONS))
        hero_ids = corpus.decks["hero_id"].to_list()
        H = np.vstack([contrib.get(h, blank) for h in hero_ids])
        scores = scores + hero_weight * H
    return scores


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
        stars = to_stars(deck_scores(corpus))
    row = corpus.deck_index.get(deck_id)
    if row is None:
        return None
    return {DIMENSIONS[j]: int(stars[row, j]) for j in range(len(DIMENSIONS))}


def render(bd):
    """Pretty star lines for a breakdown dict."""
    return "\n".join(f"  {d:16}{'★' * bd[d]}{'☆' * (5 - bd[d])}" for d in DIMENSIONS)
