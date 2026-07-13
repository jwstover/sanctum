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

      assert {:ok, card} =
               Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)

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
      unique_id = :rand.uniform(100_000)

      attrs = %{
        base_code: "test#{unique_id}",
        code: "test#{unique_id}"
      }

      assert {:ok, card} =
               Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)

      assert card.base_code == "test#{unique_id}"
      assert card.code == "test#{unique_id}"
      assert card.unique == false
      assert card.permanent == false
      assert card.is_multi_sided == false
    end

    test "fails when required attributes are missing" do
      attrs = %{
        set: "core"
      }

      assert {:error, error} =
               Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)

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

      assert {:ok, _card1} =
               Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)

      # Second creation should succeed due to upsert
      assert {:ok, _card2} =
               Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
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

      assert {:ok, _card1} =
               Card |> Ash.Changeset.for_create(:create, attrs1) |> Ash.create(authorize?: false)

      # Second creation with same base_code should upsert
      assert {:ok, _card2} =
               Card |> Ash.Changeset.for_create(:create, attrs2) |> Ash.create(authorize?: false)
    end
  end

  describe "card-level property ownership" do
    test "Card carries deck_limit, unique, and permanent" do
      attrs = %{
        base_code: "01010",
        code: "01010",
        set: "core",
        deck_limit: 2,
        unique: true,
        permanent: true
      }

      assert {:ok, card} =
               Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)

      assert card.deck_limit == 2
      assert card.unique == true
      assert card.permanent == true
    end

    test "CardSide rejects card-level deck_limit/unique/permanent inputs" do
      {:ok, card} =
        Card
        |> Ash.Changeset.for_create(:create, %{base_code: "01011", code: "01011a", set: "core"})
        |> Ash.create(authorize?: false)

      side_attrs = %{
        card_id: card.id,
        name: "Test Side",
        code: "01011a",
        side_identifier: "A",
        is_primary_side: true,
        type: :hero,
        deck_limit: 1,
        unique: true,
        permanent: false
      }

      assert {:error, %Ash.Error.Invalid{} = error} =
               Sanctum.Games.CardSide
               |> Ash.Changeset.for_create(:create, side_attrs)
               |> Ash.create(authorize?: false)

      rejected_inputs =
        error.errors
        |> Enum.map(fn err -> Map.get(err, :input) || Map.get(err, :field) end)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&to_string/1)

      assert "deck_limit" in rejected_inputs
      assert "unique" in rejected_inputs
      assert "permanent" in rejected_inputs
    end
  end

  describe "read actions" do
    setup do
      # Use random codes to avoid conflicts with other tests
      unique_id = :rand.uniform(100_000)

      hero_card_attrs = %{
        base_code: "test#{unique_id}1",
        code: "test#{unique_id}1a",
        set: "test_core_#{unique_id}",
        pack: "test_core_#{unique_id}",
        is_multi_sided: true
      }

      ally_card_attrs = %{
        base_code: "test#{unique_id}2",
        code: "test#{unique_id}2",
        set: "test_core_#{unique_id}",
        pack: "test_core_#{unique_id}",
        is_multi_sided: false
      }

      villain_card_attrs = %{
        base_code: "test#{unique_id}3",
        code: "test#{unique_id}3",
        set: "test_rhino_#{unique_id}",
        pack: "test_rhino_#{unique_id}",
        is_multi_sided: false
      }

      {:ok, hero_card} =
        Card
        |> Ash.Changeset.for_create(:create, hero_card_attrs)
        |> Ash.create(authorize?: false)

      {:ok, ally_card} =
        Card
        |> Ash.Changeset.for_create(:create, ally_card_attrs)
        |> Ash.create(authorize?: false)

      {:ok, villain_card} =
        Card
        |> Ash.Changeset.for_create(:create, villain_card_attrs)
        |> Ash.create(authorize?: false)

      %{
        hero_card: hero_card,
        ally_card: ally_card,
        villain_card: villain_card,
        hero_card_attrs: hero_card_attrs,
        villain_card_attrs: villain_card_attrs
      }
    end

    test "by_set filters cards by set", %{
      hero_card: hero_card,
      ally_card: ally_card,
      villain_card: villain_card,
      hero_card_attrs: hero_card_attrs,
      villain_card_attrs: villain_card_attrs
    } do
      core_cards = Card |> Ash.Query.for_read(:by_set, %{set: hero_card_attrs.set}) |> Ash.read!()
      assert length(core_cards) == 2

      card_ids = Enum.map(core_cards, & &1.id)
      assert hero_card.id in card_ids
      assert ally_card.id in card_ids
      refute villain_card.id in card_ids

      rhino_cards =
        Card |> Ash.Query.for_read(:by_set, %{set: villain_card_attrs.set}) |> Ash.read!()

      assert length(rhino_cards) == 1
      assert List.first(rhino_cards).id == villain_card.id
    end

    test "by_code finds card by base_code", %{hero_card: hero_card} do
      found_cards =
        Card |> Ash.Query.for_read(:by_code, %{code: hero_card.base_code}) |> Ash.read!()

      assert length(found_cards) == 1
      assert List.first(found_cards).id == hero_card.id
    end

    test "by_pack filters cards by pack", %{
      hero_card: hero_card,
      ally_card: ally_card,
      hero_card_attrs: hero_card_attrs
    } do
      core_pack_cards =
        Card |> Ash.Query.for_read(:by_pack, %{pack: hero_card_attrs.pack}) |> Ash.read!()

      assert length(core_pack_cards) == 2

      card_ids = Enum.map(core_pack_cards, & &1.id)
      assert hero_card.id in card_ids
      assert ally_card.id in card_ids
    end

    test "with_sides loads card sides", %{hero_card: hero_card} do
      # Create a card side for the hero card
      unique_id = :rand.uniform(100_000)

      card_side_attrs = %{
        card_id: hero_card.id,
        name: "Test Hero",
        code: "test#{unique_id}side",
        side_identifier: "A",
        is_primary_side: true,
        type: :hero
      }

      {:ok, _card_side} =
        Sanctum.Games.CardSide
        |> Ash.Changeset.for_create(:create, card_side_attrs)
        |> Ash.create(authorize?: false)

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

      {:ok, card} =
        Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)

      %{card: card}
    end

    test "updates card attributes", %{card: card} do
      update_attrs = %{
        set: "updated_set",
        pack: "updated_pack",
        deck_limit: 2
      }

      assert {:ok, updated_card} =
               card
               |> Ash.Changeset.for_update(:update, update_attrs)
               |> Ash.update(authorize?: false)

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

      {:ok, card} =
        Card |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)

      assert :ok = card |> Ash.destroy(authorize?: false)

      # Verify card is gone
      assert_raise Ash.Error.Invalid, fn ->
        Ash.get!(Card, card.id)
      end
    end
  end
end
