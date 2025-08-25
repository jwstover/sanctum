defmodule Sanctum.Games.Changes.CreateGameEncounterDeck do
  @moduledoc false

  alias Ash.Changeset

  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    game_id = Changeset.get_attribute(changeset, :id)

    # First create the encounter deck
    encounter_deck_attrs = %{
      game_id: game_id
    }

    changeset =
      Changeset.manage_relationship(changeset, :encounter_deck, encounter_deck_attrs,
        type: :direct_control
      )

    # Then create the encounter cards after the game and encounter deck are created
    Changeset.after_action(changeset, fn _changeset, game ->
      create_encounter_cards(game)
      {:ok, game}
    end)
  end

  defp create_encounter_cards(game) do
    scenario_id = game.scenario_id
    modular_sets = game.modular_sets || []

    case scenario_id do
      scenario_id when is_binary(scenario_id) ->
        scenario = Sanctum.Games.get_scenario!(scenario_id, load: [:encounter_cards])

        # Get encounter cards from scenario
        scenario_cards = scenario.encounter_cards || []

        # Get modular set cards if any are specified
        modular_cards = get_modular_set_cards(modular_sets)

        # Combine and shuffle encounter cards
        all_encounter_cards = scenario_cards ++ modular_cards

        # Create the encounter game cards
        if game.encounter_deck do
          create_encounter_game_cards(game.encounter_deck.id, all_encounter_cards)
        end

      _ ->
        :ok
    end
  end

  defp get_modular_set_cards(modular_sets) do
    if Enum.empty?(modular_sets) do
      []
    else
      Sanctum.Games.Card
      |> Ash.Query.filter(set in ^modular_sets)
      |> Ash.Query.filter(type != :villain)
      |> Ash.Query.filter(type != :main_scheme)
      |> Ash.read!(domain: Sanctum.Games)
    end
  end

  defp create_encounter_game_cards(encounter_deck_id, encounter_cards) do
    cards =
      encounter_cards
      |> Enum.shuffle()
      |> Enum.with_index()
      |> Enum.map(fn {card, index} ->
        %{
          order: index,
          card_id: card.id,
          game_encounter_deck_id: encounter_deck_id,
          zone: :encounter_deck,
          face_up: false
        }
      end)

    # Create all the game cards
    Enum.each(cards, fn card_attrs ->
      Sanctum.Games.GameCard
      |> Ash.Changeset.for_create(:create, card_attrs)
      |> Ash.create!(domain: Sanctum.Games)
    end)
  end
end
