"""Load an experiment YAML into an attribute-accessible tree + a stable hash.

An experiment IS its config file. `config_hash` (over the canonical raw dict)
plus the snapshot's `snapshot_hash` key every leaderboard row, so only runs on
the same corpus + settings are ever compared.
"""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from types import SimpleNamespace

import yaml

_INTERP = re.compile(r"\$\{([^}]+)\}")


def load_config(path: str | Path):
    raw = yaml.safe_load(Path(path).read_text())
    raw = _interpolate(raw, raw)
    cfg = _ns(raw)
    cfg._raw = raw
    cfg._hash = config_hash(raw)
    cfg._path = str(path)
    return cfg


def config_hash(raw: dict) -> str:
    blob = json.dumps(raw, sort_keys=True, default=str)
    return hashlib.sha1(blob.encode()).hexdigest()[:12]


def get(ns, path: str, default=None):
    """Safe dotted lookup: get(cfg, 'clustering.hdbscan.min_samples', 10)."""
    cur = ns
    for part in path.split("."):
        cur = getattr(cur, part, None) if not isinstance(cur, dict) else cur.get(part)
        if cur is None:
            return default
    return cur


# --- internals ---------------------------------------------------------------
def _ns(o):
    if isinstance(o, dict):
        return SimpleNamespace(**{k: _ns(v) for k, v in o.items()})
    if isinstance(o, list):
        return [_ns(v) for v in o]
    return o


def _interpolate(node, root):
    """Resolve ${a.b.c} references against the root dict (one shallow pass)."""
    if isinstance(node, dict):
        return {k: _interpolate(v, root) for k, v in node.items()}
    if isinstance(node, list):
        return [_interpolate(v, root) for v in node]
    if isinstance(node, str):
        return _INTERP.sub(lambda m: str(_dig(root, m.group(1))), node)
    return node


def _dig(root, dotted):
    cur = root
    for part in dotted.split("."):
        cur = cur[part]
    return cur
