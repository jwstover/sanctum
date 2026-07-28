"""Calibrate the playstyle scorer against human ratings mined from deck writeups.

MarvelCDB writeups often include a star-rating table (Damage ★★★★★, Threat
Control ★★☆☆☆, ...). Dump `{deck_id, description}` for decks whose
`description_md` contains a ★, parse the ratings, and report the Spearman
correlation between `playstyle`'s scores and the human stars per dimension.
This is the ground-truth loop the heuristics in `playstyle.py` were tuned on.

    # dump rated decks first (Elixir side), e.g.:
    #   SELECT id, description_md FROM decks WHERE description_md LIKE '%★%'
    # then:
    python -m deck_archetypes.analysis.calibrate_playstyle \
        --rated rated_decks.jsonl --snapshot snapshots/<date>

Re-run whenever more rated decks appear or the heuristics change; a rising mean
Spearman means the scorer better matches human intuition.
"""

from __future__ import annotations

import argparse
import json
import re

import numpy as np
from scipy.stats import spearmanr

from ..config import load_config
from ..preprocess import build_corpus
from ..snapshot import load_snapshot
from . import playstyle as ps


def parse_ratings(description: str) -> dict:
    """{dimension: n_stars} parsed from one description's rating table."""
    out = {}
    for dim in ps.DIMENSIONS:
        m = re.search(re.escape(dim) + r"[^★☆\n]{0,15}([★☆]{3,7})", description or "")
        if m:
            out[dim] = m.group(1).count("★")
    return out


def calibrate(rated_path: str, snapshot_dir: str, config_path: str):
    rated = {}
    for line in open(rated_path):
        r = json.loads(line)
        parsed = parse_ratings(r.get("description", ""))
        if parsed:
            rated[r["deck_id"]] = parsed

    snap = load_snapshot(snapshot_dir)
    corpus = build_corpus(snap, load_config(config_path))
    stars_scores = ps.deck_scores(corpus, heroes=snap.heroes)
    ids = [d for d in rated if d in corpus.deck_index]

    print(f"parsed {len(rated)} rated decks; {len(ids)} present in corpus\n")
    print(f"{'dimension':16}{'spearman':>9}{'n':>5}")
    rhos = []
    for j, dim in enumerate(ps.DIMENSIONS):
        xs = [stars_scores[corpus.deck_index[k], j] for k in ids if dim in rated[k]]
        ys = [rated[k][dim] for k in ids if dim in rated[k]]
        if len(xs) > 5:
            rho, _ = spearmanr(xs, ys)
            rhos.append(rho)
            print(f"{dim:16}{rho:9.3f}{len(xs):>5}")
    print(f"{'MEAN':16}{np.mean(rhos):9.3f}")
    return rhos


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rated", required=True, help="NDJSON of {deck_id, description}")
    ap.add_argument("--snapshot", required=True)
    ap.add_argument("--config", default="configs/playstyle.yaml")
    args = ap.parse_args()
    calibrate(args.rated, args.snapshot, args.config)


if __name__ == "__main__":
    main()
