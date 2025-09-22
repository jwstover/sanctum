defmodule Sanctum.MarvelCdbTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  alias Sanctum.MarvelCdb

  @tag :skip
  test "loads a decklist" do
    mcdb_deck_id = "50919"

    assert {:ok, _} = MarvelCdb.load_deck(mcdb_deck_id)
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

    test "detect_multi_sided_card/3" do
      # Explicit double_sided true
      assert MarvelCdb.detect_multi_sided_card(%{"double_sided" => true}, "01001", "a") == true

      # Has side suffix
      assert MarvelCdb.detect_multi_sided_card(%{"double_sided" => false}, "01001a", "a") == true
      assert MarvelCdb.detect_multi_sided_card(%{"double_sided" => false}, "01001b", "b") == true

      # Single sided
      assert MarvelCdb.detect_multi_sided_card(%{"double_sided" => false}, "01042", "a") == false
    end

    test "should_create_card_side?/3" do
      # Should create side for codes with suffix
      assert MarvelCdb.should_create_card_side?(%{"double_sided" => false}, "01001a", "a") == true
      assert MarvelCdb.should_create_card_side?(%{"double_sided" => true}, "01001b", "b") == true

      # Should create side for single-sided cards (no suffix, double_sided false)
      assert MarvelCdb.should_create_card_side?(%{"double_sided" => false}, "01042", "a") == true

      # Should NOT create side for base cards (no suffix, double_sided true)
      assert MarvelCdb.should_create_card_side?(%{"double_sided" => true}, "01001", "a") == false
    end
  end

  test "loads spider man hero" do
    card = MarvelCdb.load_card("01001a")
    |> IO.inspect(label: "================== \n")
  end
end
