defmodule Sanctum.Villains.VillainTest do
  use Sanctum.DataCase, async: true

  alias Sanctum.Villains

  describe "create villain" do
    test "creates a villain with valid attributes" do
      attrs = %{
        villain_name: "Rhino",
        set: "core"
      }

      assert {:ok, villain} = Villains.create_villain(attrs)
      assert villain.villain_name == "Rhino"
      assert villain.set == "core"
    end

    test "requires villain_name" do
      attrs = %{
        set: "core"
      }

      assert {:error, %Ash.Error.Invalid{}} = Villains.create_villain(attrs)
    end

    test "requires set" do
      attrs = %{
        villain_name: "Rhino"
      }

      assert {:error, %Ash.Error.Invalid{}} = Villains.create_villain(attrs)
    end
  end

  describe "find_or_create villain" do
    test "creates new villain when none exists" do
      attrs = %{
        villain_name: "Green Goblin",
        set: "green_goblin"
      }

      assert {:ok, villain} = Villains.find_or_create_villain(attrs)
      assert villain.villain_name == "Green Goblin"
      assert villain.set == "green_goblin"
    end

    test "returns existing villain when it exists" do
      attrs = %{
        villain_name: "Ultron",
        set: "age_of_ultron"
      }

      # Create the first time
      assert {:ok, villain1} = Villains.find_or_create_villain(attrs)

      # Should return the same villain the second time
      assert {:ok, villain2} = Villains.find_or_create_villain(attrs)

      assert villain1.id == villain2.id
      assert villain1.villain_name == villain2.villain_name
      assert villain1.set == villain2.set
    end

    test "creates separate villains for different sets" do
      attrs1 = %{
        villain_name: "Loki",
        set: "core"
      }

      attrs2 = %{
        villain_name: "Loki",
        set: "thor"
      }

      assert {:ok, villain1} = Villains.find_or_create_villain(attrs1)
      assert {:ok, villain2} = Villains.find_or_create_villain(attrs2)

      assert villain1.id != villain2.id
      assert villain1.villain_name == villain2.villain_name
      assert villain1.set != villain2.set
    end

    test "creates separate villains for different names" do
      attrs1 = %{
        villain_name: "Klaw",
        set: "core"
      }

      attrs2 = %{
        villain_name: "Rhino",
        set: "core"
      }

      assert {:ok, villain1} = Villains.find_or_create_villain(attrs1)
      assert {:ok, villain2} = Villains.find_or_create_villain(attrs2)

      assert villain1.id != villain2.id
      assert villain1.villain_name != villain2.villain_name
      assert villain1.set == villain2.set
    end
  end

  describe "stage_sides relationship" do
    test "loads villain stage sides by name matching" do
      set_name = "test_stages_#{:rand.uniform(100_000)}"
      villain_name = "Test Multi-Stage"

      # Create villain
      {:ok, villain} = Villains.find_or_create_villain(%{
        villain_name: villain_name,
        set: set_name
      })

      # Create cards and sides for different stages
      {:ok, stage1_card} =
        Sanctum.Games.Card
        |> Ash.Changeset.for_create(:create, %{
          base_code: "test1",
          code: "test1",
          set: set_name,
          pack: set_name
        })
        |> Ash.create()

      {:ok, stage1_side} =
        Sanctum.Games.CardSide
        |> Ash.Changeset.for_create(:create, %{
          card_id: stage1_card.id,
          name: villain_name,
          code: "test1",
          side_identifier: "A",
          is_primary_side: true,
          type: :villain,
          stage: 1
        })
        |> Ash.create()

      {:ok, stage2_card} =
        Sanctum.Games.Card
        |> Ash.Changeset.for_create(:create, %{
          base_code: "test2",
          code: "test2",
          set: set_name,
          pack: set_name
        })
        |> Ash.create()

      {:ok, stage2_side} =
        Sanctum.Games.CardSide
        |> Ash.Changeset.for_create(:create, %{
          card_id: stage2_card.id,
          name: villain_name,
          code: "test2",
          side_identifier: "A",
          is_primary_side: true,
          type: :villain,
          stage: 2
        })
        |> Ash.create()

      # Create a non-villain side that shouldn't be included
      {:ok, non_villain_side} =
        Sanctum.Games.CardSide
        |> Ash.Changeset.for_create(:create, %{
          card_id: stage1_card.id,
          name: villain_name,
          code: "test1hero",
          side_identifier: "B",
          is_primary_side: false,
          type: :hero,
          stage: 1
        })
        |> Ash.create()

      # Load villain with stage sides
      loaded_villain = Ash.load!(villain, [:stage_sides])

      # Should have exactly 2 villain sides
      assert length(loaded_villain.stage_sides) == 2

      side_ids = Enum.map(loaded_villain.stage_sides, & &1.id)
      assert stage1_side.id in side_ids
      assert stage2_side.id in side_ids
      refute non_villain_side.id in side_ids

      # Verify they're ordered by stage
      stages = Enum.map(loaded_villain.stage_sides, & &1.stage) |> Enum.sort()
      assert stages == [1, 2]
    end

    test "only includes sides with matching villain name" do
      set_name = "test_name_match_#{:rand.uniform(100_000)}"
      villain_name = "Specific Villain"
      other_villain_name = "Other Villain"

      # Create villain
      {:ok, villain} = Villains.find_or_create_villain(%{
        villain_name: villain_name,
        set: set_name
      })

      # Create card
      {:ok, card} =
        Sanctum.Games.Card
        |> Ash.Changeset.for_create(:create, %{
          base_code: "test",
          code: "test",
          set: set_name,
          pack: set_name
        })
        |> Ash.create()

      # Create matching side
      {:ok, matching_side} =
        Sanctum.Games.CardSide
        |> Ash.Changeset.for_create(:create, %{
          card_id: card.id,
          name: villain_name,
          code: "test1",
          side_identifier: "A",
          is_primary_side: true,
          type: :villain,
          stage: 1
        })
        |> Ash.create()

      # Create non-matching side (different name)
      {:ok, _non_matching_side} =
        Sanctum.Games.CardSide
        |> Ash.Changeset.for_create(:create, %{
          card_id: card.id,
          name: other_villain_name,
          code: "test2",
          side_identifier: "B",
          is_primary_side: false,
          type: :villain,
          stage: 1
        })
        |> Ash.create()

      # Load villain with stage sides
      loaded_villain = Ash.load!(villain, [:stage_sides])

      # Should have exactly 1 side (only the matching name)
      assert length(loaded_villain.stage_sides) == 1
      assert hd(loaded_villain.stage_sides).id == matching_side.id
    end
  end

  describe "read actions" do
    test "get_by_set filters villains by set" do
      set1 = "test_set_1_#{:rand.uniform(100_000)}"
      set2 = "test_set_2_#{:rand.uniform(100_000)}"

      # Create villains in different sets
      {:ok, villain1} = Villains.find_or_create_villain(%{
        villain_name: "Villain A",
        set: set1
      })

      {:ok, _villain2} = Villains.find_or_create_villain(%{
        villain_name: "Villain B",
        set: set2
      })

      {:ok, villain3} = Villains.find_or_create_villain(%{
        villain_name: "Villain C",
        set: set1
      })

      # Get villains by set1
      {:ok, set1_villains} = Villains.get_by_set(set1)

      villain_ids = Enum.map(set1_villains, & &1.id)
      assert villain1.id in villain_ids
      assert villain3.id in villain_ids
      assert length(set1_villains) == 2
    end
  end
end