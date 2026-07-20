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

  require Ash.Query

  @doc """
  Removes a pack from the actor's collection. Idempotent — a no-op when the
  pack isn't in the collection. Leaves card overrides alone: a stale
  `:excluded` row is harmless (the card is unowned either way) and an
  `:owned` row keeps meaning "I own this card regardless of packs".
  """
  def remove_pack(pack_id, actor) do
    Sanctum.Collections.CollectionPack
    |> Ash.Query.filter(pack_id == ^pack_id)
    |> Ash.bulk_destroy!(:destroy, %{}, actor: actor)

    :ok
  end

  @doc """
  Flips the actor's effective ownership of a card and returns the new state.

  An override row only ever exists when it deviates from the pack-derived
  state: flipping back toward what the packs already say destroys the
  override instead of recording a redundant one.
  """
  def toggle_card(card_id, actor) when not is_nil(actor) do
    card =
      Ash.get!(Sanctum.Games.Card, card_id,
        actor: actor,
        load: [:owned, :owned_via_packs]
      )

    case {card.owned, card.owned_via_packs} do
      {true, true} ->
        set_card_status!(card.id, :excluded, actor: actor)
        false

      {true, false} ->
        destroy_override(card.id, actor)
        false

      {false, true} ->
        destroy_override(card.id, actor)
        true

      {false, false} ->
        set_card_status!(card.id, :owned, actor: actor)
        true
    end
  end

  @doc "MapSet of pack ids in the actor's collection (empty for nil actor)."
  def owned_pack_ids(nil), do: MapSet.new()

  def owned_pack_ids(actor) do
    [actor: actor]
    |> list_collection_packs!()
    |> MapSet.new(& &1.pack_id)
  end

  @doc "Whether the given pack is in the actor's collection."
  def pack_owned?(_pack_id, nil), do: false

  def pack_owned?(pack_id, actor) do
    Sanctum.Collections.CollectionPack
    |> Ash.Query.filter(pack_id == ^pack_id)
    |> Ash.exists?(actor: actor)
  end

  defp destroy_override(card_id, actor) do
    Sanctum.Collections.CollectionCard
    |> Ash.Query.filter(card_id == ^card_id)
    |> Ash.bulk_destroy!(:destroy, %{}, actor: actor)
  end
end
