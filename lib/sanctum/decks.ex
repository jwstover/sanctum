defmodule Sanctum.Decks do
  @moduledoc false

  use Ash.Domain, otp_app: :sanctum, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Sanctum.Decks.Deck do
      define :create_with_cards, action: :create_with_cards
      define :list_decks, action: :read
      define :get_deck_by_mcdb_id, action: :read, get_by: :mcdb_id, not_found_error?: false
    end

    resource Sanctum.Decks.DeckCard
  end
end
