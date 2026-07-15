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
end
