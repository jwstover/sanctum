"""Deck-level STRUCTURAL summary — Channel 2 of the deck vector.

This is the channel that captures a deck's *statistical shape* — the thing
mean-pooling card embeddings throws away. Archetypes like "cheap allies",
"low-cost event tempo", and "few splashy high-cost finishers" are properties of
the whole deck's distribution, not of any single card.

The feature list is LOCKED to the `deck_vector.structural.features` block in the
config. Each toggle here maps to one contribution below. Everything is
quantity-weighted (a 3x card counts three times) unless noted.

Design note: prefer HAND-DESIGNED, interpretable features over a learned deck
autoencoder — clusters get named by hand, and readable features are what make
"why did this cluster form" answerable.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class StructuralConfig:
    enabled: bool
    normalize: str                 # "fractions" | "counts" | "both"
    cost_by_type_crosstab: bool
    type_mix: bool
    trait_distribution: bool
    cost_curve: bool
    cost_variance: bool
    cost_gini: bool
    high_cost_count: bool
    type_entropy: bool
    ally_atk_per_cost: bool
    ally_thw_per_cost: bool
    resource_profile: bool
    count_features: dict[str, bool]


def build(decks, cards, cfg: StructuralConfig, cost_bucket_edges: list[int]):
    """Return (matrix, feature_names).

    matrix: float array [n_decks, n_structural_features], rows aligned to the
            deck ordering used everywhere else in the pipeline. NOT yet
            normalized/weighted across channels — fusion.py owns that.
    feature_names: human-readable names, kept so interpret.py can print a
            cluster's structural profile ("mean cost curve", "type mix").

    Contributions (each gated by its config toggle):

      cost_by_type_crosstab  ★ the discriminative one.
          cost-bucket (from cost_bucket_edges) × card-type matrix, flattened.
          Distinguishes "cheap allies" (mass in ally×[0-1]) from "cheap events"
          (event×[0-1]) — a flat cost curve cannot.
      type_mix               fraction of deck per card type.
      trait_distribution     fraction of cards carrying each trait (multi-hot mean).
      cost_curve             flat cost-bucket histogram (marginal of the crosstab).
      cost_variance/gini     spread of the cost distribution — "splashiness".
      high_cost_count        # distinct 4+ cost cards — the finisher count.
      type_entropy           low == focused mono-type deck.
      ally_atk_per_cost      mean ATK/cost over allies — aggro-ally signal.
      ally_thw_per_cost      mean THW/cost over allies — thwart-ally signal.
      resource_profile       deck's total phys/mental/energy/wild generation.
      count_features         raw absolute counts (n_allies, n_events,
                             n_upgrades_supports, n_cheap_0_1, n_expensive_4plus).

    `normalize == "both"` emits fraction AND raw-count variants where both are
    meaningful (some archetypes are ratios, some are absolute counts).
    """
    raise NotImplementedError
