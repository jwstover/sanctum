defmodule Sanctum.Decks do
  @moduledoc false

  use Ash.Domain, otp_app: :sanctum, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Sanctum.Decks.Deck do
      define :get_deck, get_by: :id, action: :read
      define :create_with_cards, action: :create_with_cards
      define :list_decks, action: :read
      define :get_deck_by_mcdb_id, action: :read, get_by: :mcdb_id, not_found_error?: false
      define :set_deck_mcdb_dates, action: :set_mcdb_dates
    end

    resource Sanctum.Decks.DeckCard

    resource Sanctum.Decks.McdbUser do
      define :find_or_create_mcdb_user, action: :find_or_create
    end

    resource Sanctum.Decks.DeckSyncState do
      define :get_deck_sync_state, action: :current
      define :set_last_synced_date, action: :set_last_synced_date, args: [:last_synced_date]
    end
  end
end
