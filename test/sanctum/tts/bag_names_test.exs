defmodule Sanctum.TTS.BagNamesTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Sanctum.Decks.SideDeck
  alias Sanctum.Games.Card
  alias Sanctum.Games.CardSide
  alias Sanctum.Heroes.Hero
  alias Sanctum.TTS.BagNames

  doctest BagNames, import: true

  defp side(attrs) do
    struct!(
      CardSide,
      Map.merge(%{name: "Test Card", subname: nil, ownership: :player, aspect: "justice"}, attrs)
    )
  end

  defp side_deck(key, name) do
    %SideDeck{key: key, name: name, source: :builtin, editable?: false, cards: []}
  end

  describe "hero_name/1 and hero_bag_names/1" do
    test "a hero with no collision keeps its printed name" do
      hero = %Hero{hero_name: "Storm", base_code: "45001", set: "storm"}

      assert BagNames.hero_name(hero) == "Storm"

      assert BagNames.hero_bag_names(hero) == %{
               identity: "Storm",
               kit: "Storm Cards",
               hp_counter: "Storm's HP Counter"
             }
    end

    test "Miles Morales gets the alter-ego suffix" do
      hero = %Hero{hero_name: "Spider-Man", base_code: "27030", set: "spider_man_morales"}

      assert BagNames.hero_bag_names(hero) == %{
               identity: "Spider-Man (Miles Morales)",
               kit: "Spider-Man (Miles Morales) Cards",
               hp_counter: "Spider-Man (Miles Morales)'s HP Counter"
             }
    end

    test "Shuri gets the alter-ego suffix" do
      hero = %Hero{hero_name: "Black Panther", base_code: "51001", set: "black_panther_shuri"}

      assert BagNames.hero_bag_names(hero) == %{
               identity: "Black Panther (Shuri)",
               kit: "Black Panther (Shuri) Cards",
               hp_counter: "Black Panther (Shuri)'s HP Counter"
             }
    end

    test "the original same-name heroes stay unsuffixed" do
      assert BagNames.hero_name(%{hero_name: "Spider-Man", base_code: "01001"}) == "Spider-Man"

      assert BagNames.hero_name(%{hero_name: "Black Panther", base_code: "01040"}) ==
               "Black Panther"
    end

    test "accepts the side-lettered card code Cerebro keys on" do
      assert BagNames.hero_name(%{hero_name: "Spider-Man", base_code: "27030a"}) ==
               "Spider-Man (Miles Morales)"
    end

    test "tolerates a missing base_code" do
      assert BagNames.hero_name(%{hero_name: "Daredevil", base_code: nil}) == "Daredevil"
    end
  end

  describe "card_lookup/1 pools" do
    test "one card per aspect pool" do
      for {aspect, pool} <- [
            {"aggression", "AggressionCards"},
            {"justice", "JusticeCards"},
            {"leadership", "LeadershipCards"},
            {"protection", "ProtectionCards"},
            {"pool", "PoolCards"}
          ] do
        assert %{pool: ^pool, name: "Test Card", subname: nil} =
                 BagNames.card_lookup(side(%{ownership: :player, aspect: aspect}))
      end
    end

    test "basic cards go to BasicCards regardless of aspect" do
      assert %{pool: "BasicCards", name: "Energy", subname: nil} =
               BagNames.card_lookup(side(%{name: "Energy", ownership: :basic, aspect: nil}))
    end

    test "hero-ownership cards produce no lookup (they ride the hero kit)" do
      assert BagNames.card_lookup(side(%{name: "Ice Slide", ownership: :hero, aspect: nil})) ==
               nil
    end

    test "encounter and campaign cards produce no lookup" do
      assert BagNames.card_lookup(side(%{ownership: :encounter, aspect: nil})) == nil
      assert BagNames.card_lookup(side(%{ownership: :campaign, aspect: nil})) == nil
    end

    test "a player card with an unmapped (custom) aspect produces no lookup" do
      assert BagNames.card_lookup(side(%{ownership: :player, aspect: "determination"})) == nil
      assert BagNames.card_lookup(side(%{ownership: :player, aspect: nil})) == nil
    end
  end

  describe "card_lookup/1 subname normalization" do
    test "nil subname stays nil" do
      assert %{subname: nil} = BagNames.card_lookup(side(%{name: "Haymaker", subname: nil}))
    end

    test "empty subname becomes nil" do
      assert %{subname: nil} = BagNames.card_lookup(side(%{name: "Haymaker", subname: ""}))
    end

    test "subname equal to name becomes nil" do
      assert %{subname: nil} =
               BagNames.card_lookup(side(%{name: "Nick Fury", subname: "Nick Fury"}))
    end

    test "a real subtitle is preserved" do
      assert %{name: "Hawkeye", subname: "Clint Barton"} =
               BagNames.card_lookup(
                 side(%{name: "Hawkeye", subname: "Clint Barton", aspect: "leadership"})
               )
    end
  end

  describe "card_lookup/1 input shapes" do
    test "accepts a Card with its primary_side loaded" do
      card = %Card{code: "01072", primary_side: side(%{name: "Haymaker", aspect: "aggression"})}

      assert BagNames.card_lookup(card) == %{
               pool: "AggressionCards",
               name: "Haymaker",
               subname: nil
             }
    end

    test "a card with no primary side produces no lookup" do
      assert BagNames.card_lookup(%Card{code: "01072", primary_side: nil}) == nil
    end

    test "raises when primary_side is not loaded" do
      assert_raise ArgumentError, ~r/primary_side/, fn ->
        BagNames.card_lookup(%Card{code: "01072"})
      end
    end
  end

  describe "side_deck_bag_name/1" do
    test "maps all five mod side decks" do
      assert BagNames.side_deck_bag_name(side_deck("storm_weather_deck", "Weather Deck")) ==
               "Storm Weather Deck"

      assert BagNames.side_deck_bag_name(
               side_deck("doctor_strange_invocation_deck", "Invocation Deck")
             ) == "Doctor Strange Invocation Deck"

      assert BagNames.side_deck_bag_name(side_deck("iceman_frostbite_deck", "Frostbite Deck")) ==
               "Iceman Frostbite Deck"

      assert BagNames.side_deck_bag_name(side_deck("hercules_gift_deck", "Gift Deck")) ==
               "Hercules Gift Deck"

      assert BagNames.side_deck_bag_name(side_deck("hercules_labor_deck", "Labor Deck")) ==
               "Hercules Labor Deck"
    end

    test "accepts the bare set slug and the catalog's unsuffixed Frostbite set" do
      assert BagNames.side_deck_bag_name("iceman_frostbite") == "Iceman Frostbite Deck"
    end

    test "returns nil for a side deck the mod does not have" do
      assert BagNames.side_deck_bag_name(side_deck("daredevil_sense_deck", "Sense Deck")) == nil
    end
  end
end
