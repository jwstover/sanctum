"""Load an NDJSON snapshot produced by `mix sanctum.export_deck_corpus`.

Coerces the stat columns (exported as text so the Elixir side never had to
guard bad data) to nullable ints, and asserts every deck-card references a card
that's actually in the catalog.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import polars as pl

_STAT_COLS = ["atk", "thw", "def", "hp"]


@dataclass
class Snapshot:
    cards: pl.DataFrame
    decks: pl.DataFrame
    deck_cards: pl.DataFrame
    manifest: dict

    @property
    def hash(self) -> str:
        return self.manifest.get("snapshot_hash", "unknown")


def load_snapshot(dirpath: str | Path) -> Snapshot:
    d = Path(dirpath)
    cards = pl.read_ndjson(d / "cards.jsonl")
    decks = pl.read_ndjson(d / "decks.jsonl")
    deck_cards = pl.read_ndjson(d / "deck_cards.jsonl")
    manifest = json.loads((d / "SNAPSHOT.json").read_text())

    cards = cards.with_columns(
        [pl.col(c).cast(pl.Int64, strict=False).alias(c) for c in _STAT_COLS]
    )

    _assert_canonicalized(cards, deck_cards)
    return Snapshot(cards=cards, decks=decks, deck_cards=deck_cards, manifest=manifest)


def _assert_canonicalized(cards: pl.DataFrame, deck_cards: pl.DataFrame) -> None:
    known = set(cards["card_id"].to_list())
    used = set(deck_cards["card_id"].unique().to_list())
    missing = used - known
    if missing:
        raise ValueError(
            f"{len(missing)} deck_card card_ids are absent from cards.jsonl "
            f"(alt/reprint leak or stale snapshot). Sample: {list(missing)[:5]}"
        )
