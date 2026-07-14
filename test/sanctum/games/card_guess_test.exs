defmodule Sanctum.Games.CardGuessTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  import Sanctum.Factory

  alias Sanctum.Games.{Card, CardGuess, CardSide, Stat}

  describe "normalize/1" do
    test "lowercases, strips a leading 'the', and drops punctuation" do
      assert CardGuess.normalize("The Vision!") == "vision"
      assert CardGuess.normalize("  Spider-Man  ") == "spiderman"
      assert CardGuess.normalize("M'Baku") == "mbaku"
      assert CardGuess.normalize(nil) == ""
    end
  end

  describe "correct?/2" do
    setup do
      card = %Card{primary_side: %CardSide{name: "Black Widow", subname: "Natasha Romanoff"}}
      {:ok, card: card}
    end

    test "exact (normalized) match wins", %{card: card} do
      assert CardGuess.correct?("black widow", card)
      assert CardGuess.correct?("Black Widow!", card)
    end

    test "a close typo wins via Jaro similarity", %{card: card} do
      assert CardGuess.correct?("Black Widdow", card)
    end

    test "the subname also matches", %{card: card} do
      assert CardGuess.correct?("Natasha Romanoff", card)
    end

    test "a far-off or empty guess fails", %{card: card} do
      refute CardGuess.correct?("Iron Man", card)
      refute CardGuess.correct?("", card)
      refute CardGuess.correct?("   ", card)
    end
  end

  describe "build_hints/1" do
    test "a player card yields the full ordered ladder" do
      side = %CardSide{
        name: "The Vision",
        subname: "Victor Shade",
        type: :ally,
        ownership: :player,
        aspect: :leadership,
        traits: ["Android", "Avenger"],
        cost: 4,
        resource_mental_count: 1,
        attack: %Stat{value: 3},
        thwart: %Stat{value: 2},
        health: %Stat{value: 4}
      }

      card = %Card{unique: true, deck_limit: 3, set: "core", pack: "core", primary_side: side}
      hints = CardGuess.build_hints(card)

      assert Enum.map(hints, & &1.key) ==
               [
                 :allegiance,
                 :nature,
                 :aspect,
                 :type,
                 :traits,
                 :cost,
                 :resources,
                 :stats,
                 :uniqueness,
                 :set,
                 :name_shape
               ]

      assert hd(hints).text =~ "player card"
      assert Enum.find(hints, &(&1.key == :aspect)).text =~ "Leadership"
      assert Enum.find(hints, &(&1.key == :type)).text =~ "Ally"
      assert Enum.find(hints, &(&1.key == :stats)).text =~ "ATK 3"
    end

    test "an encounter card skips the aspect/cost/resource/stat rungs" do
      side = %CardSide{
        name: "Shadow of the Past",
        type: :treachery,
        ownership: :encounter,
        traits: []
      }

      card = %Card{unique: false, deck_limit: nil, set: "rhino", pack: "core", primary_side: side}
      hints = CardGuess.build_hints(card)
      keys = Enum.map(hints, & &1.key)

      assert hd(hints).text =~ "encounter card"
      assert :allegiance in keys
      assert :set in keys
      assert :name_shape in keys
      refute :aspect in keys
      refute :cost in keys
      refute :resources in keys
      refute :stats in keys
      refute :uniqueness in keys
    end
  end

  describe "random_guessable_card/0" do
    test "returns a flavor-bearing card with its primary side loaded" do
      card = create(Card, attrs: %{base_code: "90001", code: "90001"})

      create(CardSide,
        attrs: %{
          card_id: card.id,
          code: "90001a",
          is_primary_side: true,
          flavor: "With great power comes great responsibility."
        }
      )

      result = CardGuess.random_guessable_card()

      assert result.id == card.id
      assert result.primary_side.flavor == "With great power comes great responsibility."
    end

    test "returns nil when no card has flavor text" do
      card = create(Card, attrs: %{base_code: "90002", code: "90002"})

      create(CardSide,
        attrs: %{card_id: card.id, code: "90002a", is_primary_side: true, flavor: nil}
      )

      assert CardGuess.random_guessable_card() == nil
    end
  end
end
