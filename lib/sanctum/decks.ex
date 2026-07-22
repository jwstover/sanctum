defmodule Sanctum.Decks do
  @moduledoc false

  use Ash.Domain, otp_app: :sanctum, extensions: [AshAdmin.Domain]

  require Ash.Query

  admin do
    show? true
  end

  resources do
    resource Sanctum.Decks.Deck do
      define :get_deck, get_by: :id, action: :read
      define :create_with_cards, action: :create_with_cards
      define :list_decks, action: :read
      define :get_deck_by_mcdb_id, get_by: :mcdb_id, action: :read, not_found_error?: false
      define :set_deck_mcdb_dates, action: :set_mcdb_dates
      define :build_deck, action: :build
      define :rename_deck, action: :rename
      define :set_deck_aspects, action: :set_aspects
      define :set_deck_description, action: :set_description
      define :destroy_deck, action: :destroy
    end

    resource Sanctum.Decks.DeckCard do
      define :set_deck_card_quantity, action: :set_quantity
    end

    resource Sanctum.Decks.McdbUser do
      define :find_or_create_mcdb_user, action: :find_or_create
    end

    resource Sanctum.Decks.DeckSyncState do
      define :get_deck_sync_state, action: :current
      define :set_last_synced_date, action: :set_last_synced_date, args: [:last_synced_date]
    end
  end

  @doc """
  The hero's signature-set cards: same set as the hero, primary side owned by
  the hero (`ownership: :hero`), excluding the identity card itself. Each is
  required in a deck at exactly `deck_limit` copies.

  Filtering by ownership (not set alone) matters — hero sets also ship
  encounter-ownership cards like obligations.
  """
  def signature_cards(hero_id) do
    hero = Ash.get!(Sanctum.Heroes.Hero, hero_id, authorize?: false)

    # authorize?: false bypasses the Card read policy, so pin to the official
    # catalog (defense-in-depth — customs have a nil set today anyway).
    Sanctum.Games.Card
    |> Ash.Query.filter(
      origin == :official and set == ^hero.set and
        exists(card_sides, is_primary_side == true and ownership == :hero) and
        not exists(card_sides, type in [:hero, :alter_ego])
    )
    |> Ash.Query.load(:primary_side)
    |> Ash.Query.sort(code: :asc)
    |> Ash.read!(authorize?: false)
  end

  @doc """
  Sets the absolute quantity for a card in a deck on the owner's behalf.
  A quantity of zero (or less) removes the row. Ownership is enforced by
  DeckCard's policies.
  """
  def set_card_quantity(deck_id, card_id, quantity, actor) when quantity <= 0 do
    Sanctum.Decks.DeckCard
    |> Ash.Query.filter(deck_id == ^deck_id and card_id == ^card_id)
    |> Ash.bulk_destroy!(:destroy, %{}, actor: actor, strategy: [:atomic, :stream])

    :removed
  end

  def set_card_quantity(deck_id, card_id, quantity, actor) do
    set_deck_card_quantity!(
      %{deck_id: deck_id, card_id: card_id, quantity: quantity},
      actor: actor
    )
  end
end
