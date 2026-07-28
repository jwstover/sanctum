"""Wire the stages from a config. This module IS the framework contract — it
shows how the swappable pieces compose. Each `# ->` is a stub module to fill in.

    from deck_archetypes.pipeline import run
    run("configs/baseline.yaml")
"""

from __future__ import annotations


def run(config_path: str) -> dict:
    # 1. Config + snapshot ----------------------------------------------------
    #  -> config.load(config_path)      validate yaml -> dataclass, compute config_hash
    #  -> snapshot.load(cfg.snapshot)   read parquet, assert canonicalization,
    #                                   carry snapshot_hash. Runs are keyed by
    #                                   (snapshot_hash, config_hash) so only
    #                                   comparable runs ever land on one board.

    # 2. Preprocess -----------------------------------------------------------
    #  -> preprocess.corpus_filter(...)   state/visibility/source/min_size, strip hero
    #  -> preprocess.card_filter(...)     min_deck_count rarity floor, staple weights
    #  -> preprocess.cost_buckets(...)    apply cost_bucket_edges

    # 3. Representation: build ONE fused vector per card ----------------------
    #  Channel A  -> representation.build(method, cfg).fit(rows).card_vectors()
    #  Channel B  -> features.text_embed.embed(cards, cfg)         (enabled from day 1)
    #  Channel C  -> features.card_features.build(cards, cfg)
    #  fuse       -> representation.fusion.fuse_card_channels(A, B, C, card_fusion_cfg)
    #                 (per-channel normalize -> weight -> concat) => card_vectors

    # 4. Deck vectors: two channels -------------------------------------------
    #  Channel 1  -> fusion.pool(card_vectors, rows, pooling_cfg)   pooled embeddings
    #  Channel 2  -> features.structural.build(decks, cards, struct_cfg, edges)
    #  combine    -> fusion.combine_deck_channels([ch1, ch2], channels_cfg)
    #                 (zscore per channel -> beta weights -> L2)  => deck_vectors

    # 5. Cluster --------------------------------------------------------------
    #  -> optional reduce (umap/pca)
    #  -> clustering.build(method, cfg).fit_predict(deck_vectors)   labels (-1 == noise)

    # 6. Evaluate -------------------------------------------------------------
    #  metrics = {}
    #  -> evaluation.held_out.evaluate(...)      ★ primary, label-free
    #  -> evaluation.anchors.evaluate(...)       vs anchors/archetypes.yaml
    #  -> evaluation.intrinsic.evaluate(...)     silhouette / DB / bootstrap
    #  -> evaluation.projection.render(...)      UMAP 2D by aspect/hero/anchor/cluster
    #  -> evaluation.interpret.report(...)       top-lift cards + structural profile

    # 7. Persist --------------------------------------------------------------
    #  -> save card/deck vectors + assignments under output.dir
    #  -> leaderboard.append(snapshot_hash, config_hash, cfg.name, metrics)

    raise NotImplementedError
