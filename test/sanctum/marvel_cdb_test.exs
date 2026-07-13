defmodule Sanctum.MarvelCdbTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  alias Sanctum.MarvelCdb

  @tag :skip
  test "loads a decklist" do
    mcdb_deck_id = "50919"

    assert {:ok, _} = MarvelCdb.load_deck(mcdb_deck_id)
  end

  @tag :external
  test "loads Rhino villain stages and creates proper Villain resource" do
    # Load the three Rhino stage cards
    rhino_stage_codes = ["01094", "01095", "01096"]

    # Load each card individually (this simulates what happens when cards are loaded)
    loaded_cards =
      Enum.map(rhino_stage_codes, fn code ->
        case MarvelCdb.load_card(code) do
          {:ok, card} -> card
          error -> flunk("Failed to load card #{code}: #{inspect(error)}")
        end
      end)

    # Verify all cards were created
    assert length(loaded_cards) == 3

    # Check that all cards are in the same set
    sets = Enum.map(loaded_cards, & &1.set) |> Enum.uniq()
    assert length(sets) == 1
    set_name = hd(sets)

    # Load all the card sides for these cards
    card_sides =
      Enum.flat_map(loaded_cards, fn card ->
        card_with_sides = Ash.load!(card, [:card_sides])
        card_with_sides.card_sides
      end)

    # Find the villain sides (should be one per card)
    villain_sides = Enum.filter(card_sides, &(&1.type == :villain))

    assert length(villain_sides) >= 3,
           "Expected at least 3 villain sides, got #{length(villain_sides)}"

    # Get the villain name from any villain side (they should all have the same name)
    villain_name = hd(villain_sides).name

    # Check that a Villain resource was created
    case Sanctum.Villains.get_by_set(set_name) do
      {:ok, villains} ->
        rhino_villain = Enum.find(villains, &(&1.villain_name == villain_name))
        assert rhino_villain, "Rhino villain not found in set #{set_name}"

        # Load the villain with its stage sides
        rhino_with_sides = Ash.load!(rhino_villain, [:stage_sides])

        # Should have at least 3 stages
        assert length(rhino_with_sides.stage_sides) >= 3,
               "Expected at least 3 stage sides, got #{length(rhino_with_sides.stage_sides)}"

        # Verify stage numbers are present
        stage_numbers =
          rhino_with_sides.stage_sides
          |> Enum.map(& &1.stage)
          |> Enum.filter(&(!is_nil(&1)))
          |> Enum.sort()

        assert 1 in stage_numbers, "Stage 1 not found"
        assert 2 in stage_numbers, "Stage 2 not found"
        assert 3 in stage_numbers, "Stage 3 not found"

        # Verify each stage has different stats (health should increase with stage)
        stages_with_health =
          rhino_with_sides.stage_sides
          |> Enum.filter(&(!is_nil(&1.health) and !is_nil(&1.stage)))
          |> Enum.sort_by(& &1.stage)

        if length(stages_with_health) >= 3 do
          [stage1, stage2, stage3 | _] = stages_with_health

          # Rhino should get stronger with each stage
          assert stage1.health <= stage2.health,
                 "Stage 2 health (#{stage2.health}) should be >= Stage 1 health (#{stage1.health})"

          assert stage2.health <= stage3.health,
                 "Stage 3 health (#{stage3.health}) should be >= Stage 2 health (#{stage2.health})"
        end

      error ->
        flunk("Failed to find villains in set #{set_name}: #{inspect(error)}")
    end
  end

  describe "helper functions" do
    test "extract_base_code/1" do
      assert MarvelCdb.extract_base_code("01001a") == "01001"
      assert MarvelCdb.extract_base_code("01001b") == "01001"
      assert MarvelCdb.extract_base_code("01001") == "01001"
      assert MarvelCdb.extract_base_code("01123c") == "01123"
    end

    test "extract_side_identifier/1" do
      assert MarvelCdb.extract_side_identifier("01001a") == "a"
      assert MarvelCdb.extract_side_identifier("01001b") == "b"
      assert MarvelCdb.extract_side_identifier("01001") == "a"
      assert MarvelCdb.extract_side_identifier("01123c") == "c"
    end
  end

  @tag :external
  test "loads spider man hero" do
    assert {:ok, _card} = MarvelCdb.load_card("01001a")
  end
end
