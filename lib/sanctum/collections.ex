defmodule Sanctum.Collections do
  @moduledoc """
  A user's physical collection: which products (packs) and individual cards
  they own.

  Ownership is stored at two grains — `CollectionPack` ("I own this product")
  and `CollectionCard` (a per-card override that always beats pack membership).
  A card's effective ownership is derived, never materialized, so packs that
  gain cards across MarvelCDB syncs stay correct automatically. Collection
  data is private: policies scope every read and write to the acting user.
  """

  use Ash.Domain, otp_app: :sanctum, extensions: [AshAdmin.Domain]

  resources do
    resource Sanctum.Collections.CollectionPack do
      define :add_pack, action: :add, args: [:pack_id]
      define :list_collection_packs, action: :for_user
    end

    resource Sanctum.Collections.CollectionCard do
      define :set_card_status, action: :set_status, args: [:card_id, :status]
      define :list_card_overrides, action: :for_user
    end
  end
end
