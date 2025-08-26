defmodule Sanctum.Games.Changes.SetGameCards do
  @moduledoc false

  alias Ash.Changeset

  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    game_player_id = Changeset.get_attribute(changeset, :id)

    case Changeset.fetch_attribute(changeset, :deck_id) do
      {:ok, deck_id} when is_binary(deck_id) ->
        deck = Sanctum.Decks.get_deck!(deck_id, load: [:cards, :hero, :alter_ego])
        changeset = Changeset.put_context(changeset, :loaded_deck, deck)

        cards =
          deck.cards
          |> Enum.shuffle()
          |> Enum.reject(&(&1.type in [:alter_ego, :main_scheme, :villian, :hero]))
          |> Enum.with_index()
          |> Enum.map(fn {card, index} ->
            %{
              order: index,
              card_id: card.id,
              game_player_id: game_player_id,
              zone:
                case card.type do
                  type when type in [:ally, :attachment, :event, :resource, :support, :upgrade] ->
                    :hero_deck

                  _ ->
                    :encounter_deck
                end
            }
          end)

        Changeset.manage_relationship(changeset, :game_cards, cards, type: :direct_control)

      _ ->
        changeset
    end
  end
end
