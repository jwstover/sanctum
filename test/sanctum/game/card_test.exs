defmodule Sanctum.Game.CardTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  alias Sanctum.Games.Card

  describe "create action" do
    test "creates a card with valid attributes" do
      attrs = %{
        name: "Spider-Man",
        card_type: :hero,
        cost: 0,
        text: "Web-Slinger ability",
        set_code: "core",
        card_number: "001",
        aspect: :justice,
        attack: 2,
        thwart: 3,
        defense: 1,
        hit_points: 10,
        recovery: 3,
        hand_size: 5,
        traits: ["Avenger", "Spider"],
        keywords: ["Web-Slinger"],
        type_code: "hero",
        type_name: "Hero",
        faction_code: "hero",
        faction_name: "Hero",
        position: 1
      }

      assert {:ok, card} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert card.name == "Spider-Man"
      assert card.card_type == :hero
      assert card.cost == 0
      assert card.aspect == :justice
      assert card.attack == 2
      assert card.thwart == 3
      assert card.defense == 1
      assert card.hit_points == 10
      assert card.recovery == 3
      assert card.hand_size == 5
      assert card.traits == ["Avenger", "Spider"]
      assert card.keywords == ["Web-Slinger"]
    end

    test "creates a card with minimal required attributes" do
      attrs = %{
        name: "Basic Resource",
        card_type: :resource,
        set_code: "core",
        card_number: "002",
        type_code: "resource",
        type_name: "Resource",
        faction_code: "basic",
        faction_name: "Basic",
        position: 2
      }

      assert {:ok, card} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert card.name == "Basic Resource"
      assert card.card_type == :resource
      assert card.quantity == 1
      assert card.unique == false
      assert card.resource_count == 0
      assert card.traits == []
      assert card.keywords == []
      assert card.boost_icons == 0
      assert card.acceleration_icon == false
    end

    test "fails when required attributes are missing" do
      attrs = %{
        card_type: :ally,
        set_code: "core"
      }

      assert {:error, error} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert %Ash.Error.Invalid{} = error
      assert Enum.any?(error.errors, &(&1.field == :name))
      assert Enum.any?(error.errors, &(&1.field == :card_number))
    end

    test "validates card_type constraint" do
      attrs = %{
        name: "Invalid Card",
        card_type: :invalid_type,
        set_code: "core",
        card_number: "003",
        type_code: "ally",
        type_name: "Ally",
        faction_code: "basic",
        faction_name: "Basic",
        position: 3
      }

      assert {:error, error} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert %Ash.Error.Invalid{} = error
      card_type_error = Enum.find(error.errors, &(&1.field == :card_type))
      assert card_type_error
      assert String.contains?(card_type_error.message, "must be one of")
    end

    test "validates aspect constraint" do
      attrs = %{
        name: "Invalid Aspect Card",
        card_type: :ally,
        aspect: :invalid_aspect,
        set_code: "core",
        card_number: "004",
        type_code: "ally",
        type_name: "Ally",
        faction_code: "basic",
        faction_name: "Basic",
        position: 4
      }

      assert {:error, error} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert %Ash.Error.Invalid{} = error
      aspect_error = Enum.find(error.errors, &(&1.field == :aspect))
      assert aspect_error
      assert String.contains?(aspect_error.message, "must be one of")
    end

    test "validates resource_type constraint" do
      attrs = %{
        name: "Invalid Resource Card",
        card_type: :resource,
        resource_type: :invalid_resource,
        set_code: "core",
        card_number: "005",
        type_code: "resource",
        type_name: "Resource",
        faction_code: "basic",
        faction_name: "Basic",
        position: 5
      }

      assert {:error, error} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert %Ash.Error.Invalid{} = error
      resource_type_error = Enum.find(error.errors, &(&1.field == :resource_type))
      assert resource_type_error
      assert String.contains?(resource_type_error.message, "must be one of")
    end

    test "validates positive integer constraints" do
      attrs = %{
        name: "Invalid Stats Card",
        card_type: :ally,
        cost: -1,
        attack: -1,
        hit_points: 0,
        quantity: 0,
        set_code: "core",
        card_number: "006",
        type_code: "ally",
        type_name: "Ally",
        faction_code: "basic",
        faction_name: "Basic",
        position: 6
      }

      assert {:error, error} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert %Ash.Error.Invalid{} = error

      cost_error = Enum.find(error.errors, &(&1.field == :cost))
      attack_error = Enum.find(error.errors, &(&1.field == :attack))
      hit_points_error = Enum.find(error.errors, &(&1.field == :hit_points))
      quantity_error = Enum.find(error.errors, &(&1.field == :quantity))

      assert cost_error && String.contains?(cost_error.message, "must be more than or equal to")

      assert attack_error &&
               String.contains?(attack_error.message, "must be more than or equal to")

      assert hit_points_error &&
               String.contains?(hit_points_error.message, "must be more than or equal to")

      assert quantity_error &&
               String.contains?(quantity_error.message, "must be more than or equal to")
    end

    test "enforces unique card identity in set" do
      attrs = %{
        name: "Duplicate Card",
        card_type: :ally,
        set_code: "core",
        card_number: "007",
        type_code: "ally",
        type_name: "Ally",
        faction_code: "basic",
        faction_name: "Basic",
        position: 7
      }

      assert {:ok, _card1} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert {:error, error} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()

      assert %Ash.Error.Invalid{} = error
      duplicate_error = Enum.find(error.errors, &(&1.field == :set_code))
      assert duplicate_error
      assert String.contains?(duplicate_error.message, "has already been taken")
    end
  end

  describe "read actions" do
    setup do
      hero_attrs = %{
        name: "Iron Man",
        card_type: :hero,
        aspect: :leadership,
        set_code: "core",
        card_number: "001",
        type_code: "hero",
        type_name: "Hero",
        faction_code: "hero",
        faction_name: "Hero",
        position: 1
      }

      ally_attrs = %{
        name: "War Machine",
        card_type: :ally,
        aspect: :leadership,
        set_code: "core",
        card_number: "002",
        type_code: "ally",
        type_name: "Ally",
        faction_code: "leadership",
        faction_name: "Leadership",
        position: 2
      }

      villain_attrs = %{
        name: "Rhino",
        card_type: :villain,
        set_code: "rhino",
        card_number: "001",
        type_code: "villain",
        type_name: "Villain",
        faction_code: "villain",
        faction_name: "Villain",
        position: 1
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

    test "by_set filters cards by set code", %{hero: hero, ally: ally, villain: villain} do
      core_cards = Card |> Ash.Query.for_read(:by_set, %{set_code: "core"}) |> Ash.read!()
      assert length(core_cards) == 2

      card_ids = Enum.map(core_cards, & &1.id)
      assert hero.id in card_ids
      assert ally.id in card_ids
      refute villain.id in card_ids

      rhino_cards = Card |> Ash.Query.for_read(:by_set, %{set_code: "rhino"}) |> Ash.read!()
      assert length(rhino_cards) == 1
      assert List.first(rhino_cards).id == villain.id
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
      assert empty_results = []
    end
  end

  describe "update action" do
    setup do
      attrs = %{
        name: "Test Card",
        card_type: :ally,
        cost: 2,
        set_code: "test",
        card_number: "001",
        attack: 1,
        thwart: 1,
        type_code: "ally",
        type_name: "Ally",
        faction_code: "basic",
        faction_name: "Basic",
        position: 1
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

    test "validates constraints on update", %{card: card} do
      update_attrs = %{cost: -1, attack: -5}

      assert {:error, error} =
               card |> Ash.Changeset.for_update(:update, update_attrs) |> Ash.update()

      assert %Ash.Error.Invalid{} = error

      cost_error = Enum.find(error.errors, &(&1.field == :cost))
      attack_error = Enum.find(error.errors, &(&1.field == :attack))

      assert cost_error && String.contains?(cost_error.message, "must be more than or equal to")

      assert attack_error &&
               String.contains?(attack_error.message, "must be more than or equal to")
    end
  end

  describe "destroy action" do
    test "destroys a card" do
      attrs = %{
        name: "Temporary Card",
        card_type: :event,
        set_code: "temp",
        card_number: "001",
        type_code: "event",
        type_name: "Event",
        faction_code: "basic",
        faction_name: "Basic",
        position: 1
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
