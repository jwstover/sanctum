defmodule Sanctum.GamesTest do
  use Sanctum.DataCase, async: true

  alias Sanctum.Games

  describe "create_scenario" do
    test "creates a scenario with valid input" do
      attrs = %{
        name: "Rhino",
        set: "rhino",
        recommended_modular_sets: ["bomb_scare"]
      }

      assert {:ok, _} = Games.create_scenario(attrs)
    end
  end
end
