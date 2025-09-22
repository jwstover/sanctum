defmodule Sanctum.Games.CardTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  alias Sanctum.Games.Card

  describe "create action" do
    test "creates a card with valid attributes" do
      attrs = %{
        base_code: "01001",
        code: "01001a",
        set: "core",
        pack: "core",
        deck_limit: 1,
        unique: true,
        permanent: false,
        is_multi_sided: false
      }

      assert {:ok, card} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert card.base_code == "01001"
      assert card.code == "01001a"
      assert card.set == "core"
      assert card.pack == "core"
      assert card.deck_limit == 1
      assert card.unique == true
      assert card.permanent == false
      assert card.is_multi_sided == false
    end

    test "creates a card with minimal required attributes" do
      attrs = %{
        base_code: "01002",
        code: "01002"
      }

      assert {:ok, card} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert card.base_code == "01002"
      assert card.code == "01002"
      assert card.unique == false
      assert card.permanent == false
      assert card.is_multi_sided == false
    end

    test "fails when required attributes are missing" do
      attrs = %{
        set: "core"
      }

      assert {:error, error} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      assert %Ash.Error.Invalid{} = error
      assert Enum.any?(error.errors, &(&1.field == :base_code))
      assert Enum.any?(error.errors, &(&1.field == :code))
    end

    test "enforces unique code identity" do
      attrs = %{
        base_code: "01007",
        code: "01007",
        set: "core"
      }

      assert {:ok, _card1} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()

      # Second creation should succeed due to upsert
      assert {:ok, _card2} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
    end

    test "enforces unique base_code identity" do
      attrs1 = %{
        base_code: "01008",
        code: "01008a",
        set: "core"
      }

      attrs2 = %{
        base_code: "01008",
        code: "01008b",
        set: "core"
      }

      assert {:ok, _card1} = Card |> Ash.Changeset.for_create(:create, attrs1) |> Ash.create()

      # Second creation with same base_code should upsert
      assert {:ok, _card2} = Card |> Ash.Changeset.for_create(:create, attrs2) |> Ash.create()
    end
  end

  describe "read actions" do
    setup do
      hero_card_attrs = %{
        base_code: "01010",
        code: "01010a",
        set: "core",
        pack: "core",
        is_multi_sided: true
      }

      ally_card_attrs = %{
        base_code: "01011",
        code: "01011",
        set: "core",
        pack: "core",
        is_multi_sided: false
      }

      villain_card_attrs = %{
        base_code: "02001",
        code: "02001",
        set: "rhino",
        pack: "rhino",
        is_multi_sided: false
      }

      {:ok, hero_card} =
        Card |> Ash.Changeset.for_create(:create, hero_card_attrs) |> Ash.create()

      {:ok, ally_card} =
        Card |> Ash.Changeset.for_create(:create, ally_card_attrs) |> Ash.create()

      {:ok, villain_card} =
        Card |> Ash.Changeset.for_create(:create, villain_card_attrs) |> Ash.create()

      %{hero_card: hero_card, ally_card: ally_card, villain_card: villain_card}
    end

    test "by_set filters cards by set", %{
      hero_card: hero_card,
      ally_card: ally_card,
      villain_card: villain_card
    } do
      core_cards = Card |> Ash.Query.for_read(:by_set, %{set: "core"}) |> Ash.read!()
      assert length(core_cards) == 2

      card_ids = Enum.map(core_cards, & &1.id)
      assert hero_card.id in card_ids
      assert ally_card.id in card_ids
      refute villain_card.id in card_ids

      rhino_cards = Card |> Ash.Query.for_read(:by_set, %{set: "rhino"}) |> Ash.read!()
      assert length(rhino_cards) == 1
      assert List.first(rhino_cards).id == villain_card.id
    end

    test "by_code finds card by base_code", %{hero_card: hero_card} do
      found_cards =
        Card |> Ash.Query.for_read(:by_code, %{code: hero_card.base_code}) |> Ash.read!()

      assert length(found_cards) == 1
      assert List.first(found_cards).id == hero_card.id
    end

    test "by_pack filters cards by pack", %{hero_card: hero_card, ally_card: ally_card} do
      core_pack_cards = Card |> Ash.Query.for_read(:by_pack, %{pack: "core"}) |> Ash.read!()
      assert length(core_pack_cards) == 2

      card_ids = Enum.map(core_pack_cards, & &1.id)
      assert hero_card.id in card_ids
      assert ally_card.id in card_ids
    end

    test "with_sides loads card sides", %{hero_card: hero_card} do
      # Create a card side for the hero card
      card_side_attrs = %{
        card_id: hero_card.id,
        name: "Test Hero",
        code: "01010a",
        side_identifier: "A",
        is_primary_side: true,
        type: :hero
      }

      {:ok, _card_side} =
        Sanctum.Games.CardSide
        |> Ash.Changeset.for_create(:create, card_side_attrs)
        |> Ash.create()

      card_with_sides =
        Card
        |> Ash.Query.for_read(:with_sides)
        |> Ash.read!()
        |> Enum.find(&(&1.id == hero_card.id))

      assert card_with_sides.card_sides != nil
      assert length(card_with_sides.card_sides) == 1
      assert card_with_sides.primary_side != nil
      assert card_with_sides.primary_side.name == "Test Hero"
    end
  end

  describe "update action" do
    setup do
      attrs = %{
        base_code: "test001",
        code: "test001",
        set: "test",
        pack: "test",
        deck_limit: 3
      }

      {:ok, card} = Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
      %{card: card}
    end

    test "updates card attributes", %{card: card} do
      update_attrs = %{
        set: "updated_set",
        pack: "updated_pack",
        deck_limit: 2
      }

      assert {:ok, updated_card} =
               card |> Ash.Changeset.for_update(:update, update_attrs) |> Ash.update()

      assert updated_card.set == "updated_set"
      assert updated_card.pack == "updated_pack"
      assert updated_card.deck_limit == 2
    end
  end

  describe "destroy action" do
    test "destroys a card" do
      attrs = %{
        base_code: "temp001",
        code: "temp001",
        set: "temp",
        pack: "temp"
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
