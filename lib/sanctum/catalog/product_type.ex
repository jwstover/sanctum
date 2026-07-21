defmodule Sanctum.Catalog.ProductType do
  @moduledoc """
  What kind of product a `Pack` is.

  MarvelCDB does not classify products, so this is curated (see
  `Sanctum.Catalog.Curated`). `:promo` catches oddballs like standalone
  organized-play modular sets (e.g. the Ronan Modular Set).
  """

  use Ash.Type.Enum,
    values: [
      :core,
      :campaign_expansion,
      :hero_pack,
      :scenario_pack,
      :promo
    ]

  @doc "Human-readable label for a product type."
  def label(:core), do: "Core Set"
  def label(:campaign_expansion), do: "Campaign Expansion"
  def label(:hero_pack), do: "Hero Pack"
  def label(:scenario_pack), do: "Scenario Pack"
  def label(:promo), do: "Promo"
  def label(_), do: "Product"
end
