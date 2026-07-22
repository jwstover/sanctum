defmodule Sanctum.Games.Changes.SetGameCards do
  @moduledoc false

  alias Ash.Changeset

  use Ash.Resource.Change

  def change(changeset, _opts, context) do
    game_player_id = Changeset.get_attribute(changeset, :id)
    game_id = Changeset.get_attribute(changeset, :game_id)

    case Changeset.fetch_attribute(changeset, :deck_id) do
      {:ok, deck_id} when is_binary(deck_id) ->
        # Read as the acting user (Ash.Context.to_opts carries actor and
        # authorize? through): the deck visibility policy then decides what a
        # player can bring into a game — published decks or their own private
        # drafts — instead of an actorless read rejecting the drafts.
        deck =
          Sanctum.Decks.get_deck!(
            deck_id,
            Ash.Context.to_opts(context,
              load: [deck_cards: [card: [:primary_side]], hero: [card: [:card_sides]]]
            )
          )

        changeset = Changeset.put_context(changeset, :loaded_deck, deck)

        # Extract hand sizes from hero card sides
        hero_card = deck.hero.card
        hero_side = Enum.find(hero_card.card_sides, &(&1.type == :hero))
        alter_ego_side = Enum.find(hero_card.card_sides, &(&1.type == :alter_ego))

        changeset =
          changeset
          |> Changeset.change_attribute(:hero_hand_size, hero_side && hero_side.hand_size)
          |> Changeset.change_attribute(
            :alter_ego_hand_size,
            alter_ego_side && alter_ego_side.hand_size
          )

        cards =
          deck.deck_cards
          |> Enum.flat_map(fn dc -> List.duplicate(dc.card, dc.quantity) end)
          |> Enum.shuffle()
          |> Enum.reject(
            &(&1.primary_side &&
                &1.primary_side.type in [:alter_ego, :main_scheme, :villain, :hero])
          )
          |> Enum.with_index()
          |> Enum.map(fn {card, index} ->
            %{
              order: index,
              card_id: card.id,
              game_player_id: game_player_id,
              game_id: game_id,
              zone:
                case card.primary_side && card.primary_side.type do
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
