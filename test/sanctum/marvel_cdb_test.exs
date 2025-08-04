defmodule Sanctum.MarvelCdbTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  alias Sanctum.MarvelCdb

  @tag :skip
  test "loads a decklist" do
    mcdb_deck_id = "50919"

    assert {:ok, _} = MarvelCdb.load_deck(mcdb_deck_id)
  end
end
