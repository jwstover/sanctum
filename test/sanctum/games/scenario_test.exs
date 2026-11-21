defmodule Sanctum.Games.ScenarioTest do
  use Sanctum.DataCase, async: true

  import Sanctum.AccountsFixtures

  alias Sanctum.Games
  alias Sanctum.Games.Scenario

  defp create_owned!(attrs, owner) do
    Scenario
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.Changeset.force_change_attribute(:owner_id, owner.id)
    |> Ash.create!(authorize?: false)
  end

  defp create_card_with_side(card_attrs, side_attrs) do
    {:ok, card} =
      Sanctum.Games.Card
      |> Ash.Changeset.for_create(:create, card_attrs)
      |> Ash.create(authorize?: false)

    {:ok, _side} =
      Sanctum.Games.CardSide
      |> Ash.Changeset.for_create(
        :create,
        Map.merge(side_attrs, %{
          card_id: card.id,
          code: card_attrs.code,
          side_identifier: "A",
          is_primary_side: true
        })
      )
      |> Ash.create(authorize?: false)

    {:ok, card}
  end

  test "derives set from the villain set" do
    vs = villain_set!("rhino")

    assert {:ok, scenario} =
             Games.create_scenario(%{name: "Rhino", villain_set_id: vs.id}, authorize?: false)

    assert scenario.set == "rhino"

    assert {:error, %Ash.Error.Invalid{}} =
             Games.create_scenario(%{name: "Rhino", villain_set_id: vs.id, set: "x"},
               authorize?: false
             )
  end

  test "rejects a non-villain set" do
    modular = create(Sanctum.Catalog.CardSet, action: :upsert)

    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             Games.create_scenario(%{name: "Bad", villain_set_id: modular.id}, authorize?: false)

    assert Enum.any?(errors, &(Map.get(&1, :field) == :villain_set_id))
  end

  test "requires a villain set" do
    assert {:error, %Ash.Error.Invalid{}} =
             Games.create_scenario(%{name: "None"}, authorize?: false)
  end

  test "only admins can create; anyone can read" do
    attrs = %{name: "Rhino", villain_set_id: villain_set!().id}

    assert {:error, %Ash.Error.Forbidden{}} = Games.create_scenario(attrs, actor: user_fixture())
    assert {:ok, _} = Games.create_scenario(attrs, actor: admin_user_fixture())
    assert {:ok, _} = Games.list_scenarios()
  end

  test "owned scenarios coexist with the official one" do
    vs = villain_set!()
    attrs = %{name: "Same", villain_set_id: vs.id}

    official = Games.create_scenario!(attrs, authorize?: false)
    a = create_owned!(attrs, user_fixture())
    b = create_owned!(attrs, user_fixture())

    assert length(Enum.uniq([official.id, a.id, b.id])) == 3
    assert Games.create_scenario!(attrs, authorize?: false).id == official.id
  end

  test "deleting a scenario nilifies games.scenario_id" do
    user = user_fixture()

    scenario =
      Games.create_scenario!(%{name: "Gone", villain_set_id: villain_set!().id},
        authorize?: false
      )

    {:ok, _villain_card} =
      create_card_with_side(
        %{base_code: "scnv01", code: "scnv01", set: scenario.set, pack: scenario.set},
        %{
          name: "Scenario Villain",
          type: :villain,
          health: %{value: 10},
          attack: %{value: 2},
          scheme: 1
        }
      )

    assert {:ok, game} =
             Games.create_game(%{scenario_id: scenario.id, modular_sets: []}, actor: user)

    Ash.destroy!(scenario, authorize?: false)
    assert Ash.reload!(game, authorize?: false).scenario_id == nil
  end

  test "a game still requires a scenario" do
    assert {:error, _} = Games.create_game(%{modular_sets: []}, actor: user_fixture())
  end
end
