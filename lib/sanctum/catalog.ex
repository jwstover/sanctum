defmodule Sanctum.Catalog do
  @moduledoc """
  Release taxonomy: `Wave` → `Pack` (product) → `CardSet`.

  Pack/CardSet metadata is sourced from MarvelCDB during card sync; the wave
  grouping and product types are curated (`Sanctum.Catalog.Curated`). This
  domain is read-open; mutations are admin-only, and sync writes with
  `authorize?: false`.
  """

  use Ash.Domain, otp_app: :sanctum, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Sanctum.Catalog.Wave do
      define :find_or_create_wave, action: :find_or_create
      define :list_waves, action: :read
    end

    resource Sanctum.Catalog.Pack do
      define :upsert_pack, action: :upsert_from_marvelcdb
      define :get_pack_by_code, args: [:code], get?: true, action: :by_code
      define :set_pack_curated, action: :set_curated
      define :list_packs, action: :read
    end

    resource Sanctum.Catalog.CardSet do
      define :upsert_card_set, action: :upsert
      define :get_card_set_by_code, args: [:code], get?: true, action: :by_code
      define :set_card_set_hero_set, action: :set_hero_set
      define :list_card_sets, action: :read
    end
  end
end
