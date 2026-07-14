defmodule Sanctum.Games.GameCardTest do
  # NOTE: async: false is required for the concurrency test below. The Ecto SQL
  # sandbox needs to run in shared mode so the spawned tasks can borrow the same
  # database connection as the test process.
  use Sanctum.DataCase, async: false

  require Ash.Query

  alias Sanctum.Games
  alias Sanctum.Games.Card
  alias Sanctum.Games.GameCard

  # Creates a card with its primary side. Card-level metadata lives on `Card`;
  # gameplay stats (name, type, health, etc.) live on the `CardSide`.
  defp create_card_with_side(card_attrs, side_attrs) do
    {:ok, card} =
      Card |> Ash.Changeset.for_create(:create, card_attrs) |> Ash.create(authorize?: false)

    side_attrs_with_card_id =
      Map.merge(side_attrs, %{
        card_id: card.id,
        code: card_attrs.code,
        side_identifier: "A",
        is_primary_side: true
      })

    {:ok, _side} =
      Sanctum.Games.CardSide
      |> Ash.Changeset.for_create(:create, side_attrs_with_card_id)
      |> Ash.create(authorize?: false)

    {:ok, card}
  end

  # Builds a game (which creates a GamePlayer) and seeds `count` cards into the
  # player's `:hero_deck` zone with gapped, increasing orders. Returns the
  # user, game_player, and the seeded game cards.
  defp build_game_with_hero_deck(count) do
    email = "test#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Sanctum.Accounts.User
      |> Ash.Changeset.for_create(:create, %{
        email: email,
        confirmed_at: DateTime.utc_now()
      })
      |> Ash.create(authorize?: false)

    set_name = "test_scenario_#{System.unique_integer([:positive])}"

    {:ok, scenario} =
      Games.create_scenario(%{
        name: "Test Scenario",
        set: set_name,
        recommended_modular_sets: []
      })

    villain_code = "testv#{System.unique_integer([:positive])}"

    {:ok, _villain_card} =
      create_card_with_side(
        %{
          base_code: villain_code,
          code: villain_code,
          set: set_name,
          pack: set_name
        },
        %{
          name: "Test Villain",
          type: :villain,
          health: %{value: 10},
          attack: %{value: 2},
          scheme: 1
        }
      )

    {:ok, game} = Games.create_game(%{scenario_id: scenario.id, modular_sets: []}, actor: user)

    game_player =
      game
      |> Ash.load!(:game_players, actor: user)
      |> Map.get(:game_players)
      |> List.first()

    game_cards =
      for i <- 1..count do
        deck_code = "deck#{System.unique_integer([:positive])}"

        {:ok, card} =
          create_card_with_side(
            %{
              base_code: deck_code,
              code: deck_code,
              set: set_name,
              pack: set_name
            },
            %{
              name: "Deck Card #{i}",
              type: :ally
            }
          )

        {:ok, game_card} =
          GameCard
          |> Ash.Changeset.for_create(:create, %{
            game_id: game.id,
            game_player_id: game_player.id,
            card_id: card.id,
            zone: :hero_deck,
            order: i * 10
          })
          |> Ash.create()

        game_card
      end

    {user, game_player, game_cards}
  end

  describe "draw_cards/3" do
    test "moves N cards to :hero_hand with unique, increasing orders" do
      {user, game_player, _game_cards} = build_game_with_hero_deck(5)

      drawn = Games.draw_cards(game_player.id, 3, actor: user)

      assert length(drawn) == 3

      for card <- drawn do
        assert card.zone == :hero_hand
        assert card.game_player_id == game_player.id
      end

      orders = Enum.map(drawn, & &1.order)

      assert orders == Enum.uniq(orders), "expected unique orders, got #{inspect(orders)}"
      assert orders == Enum.sort(orders), "expected increasing orders, got #{inspect(orders)}"

      # Gapped ordering (increments of 10) starting from an empty hand.
      assert orders == [10, 20, 30]

      # The drawn cards should now be the only cards in the hand.
      hand =
        GameCard
        |> Ash.Query.filter(game_player_id == ^game_player.id and zone == :hero_hand)
        |> Ash.read!(authorize?: false)

      assert length(hand) == 3
    end
  end

  describe "concurrent moves into the same zone" do
    # CAVEAT: The Ecto SQL sandbox shares a single database connection across
    # the test and any tasks it spawns (shared mode). That means these moves are
    # ultimately serialized by the connection, so this test cannot exercise true
    # OS-level parallelism or observe advisory-lock contention. What it *does*
    # prove is that many moves into the same (game_player, zone) — issued through
    # `Task.async_stream` rather than a straight loop — each read the current
    # max(order) and produce a unique, non-colliding order. The race-safety of
    # the advisory lock under genuine parallelism is verified out-of-band (see
    # PR "How to verify"), since the sandbox precludes it here.
    test "all resulting orders are unique" do
      {user, game_player, game_cards} = build_game_with_hero_deck(10)

      parent = self()
      Ecto.Adapters.SQL.Sandbox.mode(Sanctum.Repo, {:shared, parent})

      moved =
        game_cards
        |> Task.async_stream(
          fn card ->
            Games.move_game_card!(
              card,
              %{game_player_id: game_player.id, zone: :hero_play},
              actor: user
            )
          end,
          max_concurrency: 10,
          ordered: false
        )
        |> Enum.map(fn {:ok, card} -> card end)

      assert length(moved) == 10

      for card <- moved do
        assert card.zone == :hero_play
      end

      orders = Enum.map(moved, & &1.order)

      assert length(Enum.uniq(orders)) == length(orders),
             "expected all unique orders, got #{inspect(Enum.sort(orders))}"
    end
  end
end
