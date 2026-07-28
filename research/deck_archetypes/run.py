#!/usr/bin/env python
"""CLI entry point for the deck-archetype harness.

    python run.py configs/baseline.yaml
    python run.py configs/baseline.yaml --snapshot-dir snapshots/2026-07-27
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "src"))

from deck_archetypes.pipeline import run  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("config")
    ap.add_argument("--snapshot-dir", default=None)
    ap.add_argument("--base-dir", default=str(Path(__file__).parent))
    args = ap.parse_args()

    metrics = run(args.config, snapshot_dir=args.snapshot_dir, base_dir=args.base_dir)

    print("\n=== metrics ===")
    for group in ("held_out", "anchors", "intrinsic"):
        if group in metrics:
            print(f"{group}: {json.dumps(metrics[group], default=str)}")


if __name__ == "__main__":
    main()
