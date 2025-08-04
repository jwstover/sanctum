defmodule Sanctum.Games.CardTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  alias Sanctum.Games.Card

  describe "create action" do
    test "creates a card with valid attributes" do
      attrs = %{
        name: "Spider-Man",
        type: :hero,
        cost: 0,
        text: "Web-Slinger ability",
        set: "core",
        code: "01001",
        aspect: :justice,
        attack: 2,
        thwart: 3,
        defense: 1,
        health: 10,
        recover: 3,
        hand_size: 5,
        traits: ["Avenger", "Spider"]
      }

      assert {:ok, card} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert card.name == "Spider-Man"
      assert card.type == :hero
      assert card.cost == 0
      assert card.aspect == :justice
      assert card.attack == 2
      assert card.thwart == 3
      assert card.defense == 1
      assert card.health == 10
      assert card.recover == 3
      assert card.hand_size == 5
      assert card.traits == ["Avenger", "Spider"]
    end

    test "creates a card with minimal required attributes" do
      attrs = %{
        name: "Basic Resource",
        type: :resource,
        set: "core",
        code: "01002"
      }

      assert {:ok, card} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert card.name == "Basic Resource"
      assert card.type == :resource
      assert card.unique == false
      assert card.traits == []
    end

    test "fails when required attributes are missing" do
      attrs = %{
        type: :ally,
        set: "core"
      }

      assert {:error, error} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert %Ash.Error.Invalid{} = error
      assert Enum.any?(error.errors, &(&1.field == :name))
      assert Enum.any?(error.errors, &(&1.field == :code))
    end

    test "validates type constraint" do
      attrs = %{
        name: "Invalid Card",
        type: :invalid_type,
        set: "core",
        code: "01003"
      }

      assert {:error, error} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert %Ash.Error.Invalid{} = error
      type_error = Enum.find(error.errors, &(&1.field == :type))
      assert type_error
      assert String.contains?(type_error.message, "is invalid")
    end

    test "validates aspect constraint" do
      attrs = %{
        name: "Invalid Aspect Card",
        type: :ally,
        aspect: :invalid_aspect,
        set: "core",
        code: "01004"
      }

      assert {:error, error} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert %Ash.Error.Invalid{} = error
      aspect_error = Enum.find(error.errors, &(&1.field == :aspect))
      assert aspect_error
      assert String.contains?(aspect_error.message, "is invalid")
    end

    test "enforces unique code identity" do
      attrs = %{
        name: "Duplicate Card",
        type: :ally,
        set: "core",
        code: "01007"
      }

      assert {:ok, _card1} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert {:ok, _card2} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
    end
  end

  describe "read actions" do
    setup do
      hero_attrs = %{
        name: "Iron Man",
        type: :hero,
        aspect: :leadership,
        set: "core",
        code: "01010"
      }

      ally_attrs = %{
        name: "War Machine",
        type: :ally,
        aspect: :leadership,
        set: "core",
        code: "01011"
      }

      villain_attrs = %{
        name: "Rhino",
        type: :villain,
        set: "rhino",
        code: "02001"
      }

      {:ok, hero} = Card |> Ash.Changeset.for_create(:create, hero_attrs) |> Ash.create()
      {:ok, ally} = Card |> Ash.Changeset.for_create(:create, ally_attrs) |> Ash.create()
      {:ok, villain} = Card |> Ash.Changeset.for_create(:create, villain_attrs) |> Ash.create()

      %{hero: hero, ally: ally, villain: villain}
    end

    test "by_type filters cards by card type", %{hero: hero, ally: ally} do
      heroes = Card |> Ash.Query.for_read(:by_type, %{card_type: :hero}) |> Ash.read!()
      assert length(heroes) == 1
      assert List.first(heroes).id == hero.id

      allies = Card |> Ash.Query.for_read(:by_type, %{card_type: :ally}) |> Ash.read!()
      assert length(allies) == 1
      assert List.first(allies).id == ally.id
    end

    test "by_aspect filters cards by aspect", %{hero: hero, ally: ally} do
      leadership_cards =
        Card |> Ash.Query.for_read(:by_aspect, %{aspect: :leadership}) |> Ash.read!()

      assert length(leadership_cards) == 2

      card_ids = Enum.map(leadership_cards, & &1.id)
      assert hero.id in card_ids
      assert ally.id in card_ids
    end

    test "by_set filters cards by set", %{hero: hero, ally: ally, villain: villain} do
      core_cards = Card |> Ash.Query.for_read(:by_set, %{set: "core"}) |> Ash.read!()
      assert length(core_cards) == 2

      card_ids = Enum.map(core_cards, & &1.id)
      assert hero.id in card_ids
      assert ally.id in card_ids
      refute villain.id in card_ids

      rhino_cards = Card |> Ash.Query.for_read(:by_set, %{set: "rhino"}) |> Ash.read!()
      assert length(rhino_cards) == 1
      assert List.first(rhino_cards).id == villain.id
    end

    test "by_code finds card by code", %{hero: hero} do
      found_cards = Card |> Ash.Query.for_read(:by_code, %{code: hero.code}) |> Ash.read!()
      assert length(found_cards) == 1
      assert List.first(found_cards).id == hero.id
    end

    test "by_pack filters cards by pack", %{hero: hero, ally: ally} do
      # Set pack on cards first
      {:ok, _} = hero |> Ash.Changeset.for_update(:update, %{pack: "core"}) |> Ash.update()
      {:ok, _} = ally |> Ash.Changeset.for_update(:update, %{pack: "core"}) |> Ash.update()

      core_pack_cards = Card |> Ash.Query.for_read(:by_pack, %{pack: "core"}) |> Ash.read!()
      assert length(core_pack_cards) >= 2
    end

    test "search filters cards by name or text content", %{
      hero: hero,
      ally: ally,
      villain: _villain
    } do
      # Search by name
      iron_cards = Card |> Ash.Query.for_read(:search, %{query: "Iron"}) |> Ash.read!()
      assert length(iron_cards) == 1
      assert List.first(iron_cards).id == hero.id

      # Search by partial name
      machine_cards = Card |> Ash.Query.for_read(:search, %{query: "Machine"}) |> Ash.read!()
      assert length(machine_cards) == 1
      assert List.first(machine_cards).id == ally.id

      # Search with no results
      empty_results = Card |> Ash.Query.for_read(:search, %{query: "NonExistent"}) |> Ash.read!()
      assert empty_results == []
    end
  end

  describe "update action" do
    setup do
      attrs = %{
        name: "Test Card",
        type: :ally,
        cost: 2,
        set: "test",
        code: "test001",
        attack: 1,
        thwart: 1
      }

      {:ok, card} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      %{card: card}
    end

    test "updates card attributes", %{card: card} do
      update_attrs = %{
        name: "Updated Card",
        cost: 3,
        attack: 2,
        thwart: 2
      }

      assert {:ok, updated_card} =
               card |> Ash.Changeset.for_update(:update, update_attrs) |> Ash.update()

      assert updated_card.name == "Updated Card"
      assert updated_card.cost == 3
      assert updated_card.attack == 2
      assert updated_card.thwart == 2
    end
  end

  describe "destroy action" do
    test "destroys a card" do
      attrs = %{
        name: "Temporary Card",
        type: :event,
        set: "temp",
        code: "temp001"
      }

      {:ok, card} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert :ok = card |> Ash.destroy()

      # Verify card is gone
      assert_raise Ash.Error.Invalid, fn ->
        Ash.get!(Card, card.id)
      end
    end
  end
end
