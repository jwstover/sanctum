"""Channel B — rules-text embeddings, aligned to the vocabulary.

Sentence-transformer embedding of each card's printed text; captures mechanical
meaning (including nuance keyword regexes miss, like "does not exhaust") and
gives rare cards a sensible position regardless of play history. Cached per
(model, snapshot) so the model only runs once per corpus.

`sentence-transformers` is imported lazily — the package stays importable
without it, and the dependency is only required when `representation.text.enabled`.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

import numpy as np

from ..config import get


def build(corpus, cfg, cache_dir: Path | None = None):
    """Return (matrix [n_cards, d], feature_names)."""
    model_name = get(cfg, "representation.text.model")
    field = get(cfg, "representation.text.source_field", "text")
    reduce_dim = get(cfg, "representation.text.reduce_dim")

    texts = [t or "" for t in corpus.cards[field].to_list()]
    emb = _embed_cached(model_name, texts, corpus, cache_dir)

    if reduce_dim and reduce_dim < emb.shape[1]:
        from sklearn.decomposition import PCA

        emb = PCA(n_components=int(reduce_dim), random_state=0).fit_transform(emb)

    return emb, [f"text_{i}" for i in range(emb.shape[1])]


def _embed_cached(model_name, texts, corpus, cache_dir):
    key = hashlib.sha1(
        (model_name + "|" + corpus.__class__.__name__ + "|" + "␟".join(texts)).encode()
    ).hexdigest()[:16]

    cache_file = None
    if cache_dir is not None:
        cache_dir = Path(cache_dir)
        cache_dir.mkdir(parents=True, exist_ok=True)
        cache_file = cache_dir / f"text_{key}.npy"
        if cache_file.exists():
            return np.load(cache_file)

    try:
        from sentence_transformers import SentenceTransformer
    except ImportError as e:  # pragma: no cover
        raise RuntimeError(
            "representation.text.enabled but sentence-transformers is not installed "
            "(`pip install sentence-transformers`). Disable the text channel to run "
            "without it."
        ) from e

    model = SentenceTransformer(model_name)
    emb = np.asarray(model.encode(texts, show_progress_bar=False, normalize_embeddings=False))

    if cache_file is not None:
        np.save(cache_file, emb)
    return emb
