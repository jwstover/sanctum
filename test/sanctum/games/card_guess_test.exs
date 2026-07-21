defmodule Sanctum.Games.CardGuessTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  import Sanctum.Factory

  alias Sanctum.Catalog.CardSet, as: CatalogCardSet
  alias Sanctum.Catalog.Pack
  alias Sanctum.Catalog.Wave
  alias Sanctum.Games.{Card, CardGuess, CardSide}

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
        text: "<b>Response</b>: After The Vision thwarts, deal 1 damage to a minion."
      }

      card = %Card{
        unique: true,
        deck_limit: 3,
        set: "core",
        pack: "core",
        pack_ref: %Pack{name: "Core Set", wave: %Wave{number: 1, name: "Wave 1"}},
        primary_side: side
      }

      hints = CardGuess.build_hints(card)

      assert Enum.map(hints, & &1.key) ==
               [:wave, :pack, :allegiance, :pool, :type, :cost, :traits, :text]

      assert Enum.at(hints, 0).text == "It was released in Wave 1."
      assert Enum.at(hints, 1).text == "It comes from the “Core Set” pack."
      assert Enum.at(hints, 2).text == "This is a player card."
      assert Enum.at(hints, 3).text == "This is a Leadership card."
      assert Enum.at(hints, 4).text == "Specifically, it's a Leadership ally."
      assert Enum.at(hints, 5).text == "It costs 4 and provides 1 mental resource icon."
      assert Enum.at(hints, 6).text == "Traits: Android, Avenger."

      # Markup stripped, the card's own name redacted.
      assert Enum.at(hints, 7).text ==
               "Its text reads: “Response: After ____ thwarts, deal 1 damage to a minion.”"
    end

    test "without a synced pack the release rungs fall back to the pack slug" do
      side = %CardSide{name: "Foresight", type: :event, ownership: :player, aspect: :justice}
      card = %Card{pack: "mutant_genesis", primary_side: side}

      hints = CardGuess.build_hints(card)

      assert Enum.map(hints, & &1.key) == [:pack, :allegiance, :pool, :type]
      assert hd(hints).text == "It comes from the “Mutant Genesis” pack."
      assert Enum.at(hints, 4) == nil
    end

    test "an encounter card names its set's role instead of repeating rung 3" do
      side = %CardSide{
        name: "Shadow of the Past",
        type: :treachery,
        ownership: :encounter,
        traits: []
      }

      card = %Card{
        set: "rhino",
        pack: "core",
        card_set: %CatalogCardSet{set_type: :villain},
        primary_side: side
      }

      hints = CardGuess.build_hints(card)

      assert Enum.map(hints, & &1.key) == [:pack, :allegiance, :pool, :type]
      assert Enum.at(hints, 1).text == "This is an encounter card."
      assert Enum.at(hints, 2).text == "It's part of a villain's encounter set."
      assert Enum.at(hints, 3).text == "Specifically, it's an encounter treachery."

      modular = %Card{card | card_set: %CatalogCardSet{set_type: :modular}}

      assert Enum.find(CardGuess.build_hints(modular), &(&1.key == :pool)).text ==
               "It's part of a modular encounter set."
    end

    test "an encounter card with no synced set skips the pool rung" do
      side = %CardSide{name: "Shadow of the Past", type: :treachery, ownership: :encounter}
      card = %Card{pack: "core", primary_side: side}

      keys = card |> CardGuess.build_hints() |> Enum.map(& &1.key)

      assert keys == [:pack, :allegiance, :type]
    end

    test "a villain-type card is called a villain, not a generic encounter card" do
      side = %CardSide{name: "Rhino", type: :villain, ownership: :encounter}
      card = %Card{pack: "core", primary_side: side}

      hints = CardGuess.build_hints(card)

      assert Enum.find(hints, &(&1.key == :pool)).text == "This is a villain card."
      assert Enum.find(hints, &(&1.key == :type)).text == "Specifically, it's a villain."
    end

    test "an X cost renders as X" do
      side = %CardSide{name: "Gambit", type: :event, ownership: :player, aspect: :pool, cost: -1}
      card = %Card{pack: "deadpool", primary_side: side}

      assert Enum.find(CardGuess.build_hints(card), &(&1.key == :cost)).text ==
               "Its resource cost is X."
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
