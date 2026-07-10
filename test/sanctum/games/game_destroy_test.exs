defmodule Sanctum.Games.GameDestroyTest do
  use Sanctum.DataCase, async: true

  alias Sanctum.Games
  alias Sanctum.Games.Card
  alias Sanctum.Games.CardSide
  alias Sanctum.Games.GameCard
  alias Sanctum.Games.GameEncounterDeck
  alias Sanctum.Games.GamePlayer
  alias Sanctum.Games.GameScheme
  alias Sanctum.Games.GameVillain

  require Ash.Query

  # Helper function to create a card with its primary side
  defp create_card_with_side(card_attrs, side_attrs) do
    {:ok, card} = Card |> Ash.Changeset.for_create(:create, card_attrs) |> Ash.create()

    side_attrs_with_card_id =
      Map.merge(side_attrs, %{
        card_id: card.id,
        code: card_attrs.code,
        side_identifier: "A",
        is_primary_side: true
      })

    {:ok, _side} =
      CardSide
      |> Ash.Changeset.for_create(:create, side_attrs_with_card_id)
      |> Ash.create()

    {:ok, card}
  end

  defp count_for_game(resource, game_id) do
    resource
    |> Ash.Query.filter(game_id == ^game_id)
    |> Ash.count!(authorize?: false)
  end

  describe "destroy_game cascade" do
    setup do
      {:ok, scenario} =
        Games.create_scenario(%{
          name: "Destroy Scenario",
          set: "destroy_scenario",
          recommended_modular_sets: []
        })

      # Villain card (drives game_villain creation)
      {:ok, _villain_card} =
        create_card_with_side(
          %{
            base_code: "destroyv01",
            code: "destroyv01",
            set: "destroy_scenario",
            pack: "destroy_scenario"
          },
          %{
            name: "Destroy Villain",
            type: :villain,
            health: 10,
            attack: 2,
            scheme: 1
          }
        )

      # Main scheme card (drives game_scheme creation)
      {:ok, _scheme_card} =
        create_card_with_side(
          %{
            base_code: "destroys01",
            code: "destroys01",
            set: "destroy_scenario",
            pack: "destroy_scenario"
          },
          %{
            name: "Destroy Scheme",
            type: :main_scheme,
            base_threat: 5,
            max_threat: 10
          }
        )

      # Encounter cards (populate the encounter deck)
      for i <- 1..3 do
        {:ok, _card} =
          create_card_with_side(
            %{
              base_code: "destroye0#{i}",
              code: "destroye0#{i}",
              set: "destroy_scenario",
              pack: "destroy_scenario"
            },
            %{
              name: "Destroy Encounter #{i}",
              type: :minion
            }
          )
      end

      {:ok, user} =
        Sanctum.Accounts.User
        |> Ash.Changeset.for_create(:create, %{
          email: "destroy@example.com",
          confirmed_at: DateTime.utc_now()
        })
        |> Ash.create(authorize?: false)

      {:ok, game} =
        Games.create_game(%{scenario_id: scenario.id, modular_sets: []}, actor: user)

      %{game: game}
    end

    test "destroying a game cascades to all game-scoped children", %{game: game} do
      # Sanity: the game created players, villain, schemes, encounter deck, and cards.
      assert count_for_game(GamePlayer, game.id) > 0
      assert count_for_game(GameVillain, game.id) > 0
      assert count_for_game(GameScheme, game.id) > 0
      assert count_for_game(GameEncounterDeck, game.id) > 0

      total_game_cards = Ash.count!(GameCard, authorize?: false)
      assert total_game_cards > 0

      # Catalog counts before destroy.
      cards_before = Ash.count!(Card, authorize?: false)
      sides_before = Ash.count!(CardSide, authorize?: false)
      assert cards_before > 0
      assert sides_before > 0

      assert :ok = Games.destroy_game(game, authorize?: false)

      # All game-scoped children are gone.
      assert count_for_game(GamePlayer, game.id) == 0
      assert count_for_game(GameVillain, game.id) == 0
      assert count_for_game(GameScheme, game.id) == 0
      assert count_for_game(GameEncounterDeck, game.id) == 0
      assert Ash.count!(GameCard, authorize?: false) == 0

      # Catalog (cards / card_sides) is untouched.
      assert Ash.count!(Card, authorize?: false) == cards_before
      assert Ash.count!(CardSide, authorize?: false) == sides_before
    end
  end
end
