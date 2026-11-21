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

  describe "user-built scenarios" do
    defp build!(user, attrs \\ %{}) do
      Games.build_scenario!(Map.put_new(attrs, :villain_set_id, villain_set!().id), actor: user)
    end

    test "a signed-out user can read but not build" do
      assert {:ok, _} = Games.list_scenarios()

      assert {:error, error} = Games.build_scenario(%{villain_set_id: villain_set!().id})
      assert error.__struct__ in [Ash.Error.Invalid, Ash.Error.Forbidden]
    end

    test "build sets the owner, derives the set and the default name" do
      user = user_fixture()
      vs = villain_set!("dflt_x")

      scenario = build!(user, %{villain_set_id: vs.id})

      assert scenario.owner_id == user.id
      assert scenario.set == vs.code
      assert scenario.name == "#{vs.name} Scenario"

      scenario = Ash.load!(scenario, [:modular_set_count, :official, :mine], actor: user)
      assert scenario.modular_set_count == 0
      assert scenario.official == false
      assert scenario.mine == true

      assert build!(user, %{name: "Custom"}).name == "Custom"
      assert build!(user, %{villain_set_id: vs.id, name: "  "}).name == "#{vs.name} Scenario"
    end

    test "builds are not upserted into the official row" do
      vs = villain_set!()
      official = Games.create_scenario!(%{name: "Off", villain_set_id: vs.id}, authorize?: false)

      a = build!(user_fixture(), %{villain_set_id: vs.id})
      b = build!(user_fixture(), %{villain_set_id: vs.id})

      assert length(Enum.uniq([official.id, a.id, b.id])) == 3
    end

    test "the owner can rename, set modular sets and destroy" do
      owner = user_fixture()
      s = build!(owner)

      assert Games.rename_scenario!(s, %{name: "Mine"}, actor: owner).name == "Mine"

      m1 = create(Sanctum.Catalog.CardSet, action: :upsert)
      m2 = create(Sanctum.Catalog.CardSet, action: :upsert)

      Games.set_scenario_modular_sets!(s, %{modular_sets: [m1.id, m2.id]}, actor: owner)
      loaded = Ash.load!(s, [:modular_sets, :modular_set_count], authorize?: false)
      assert loaded.modular_set_count == 2
      assert Enum.sort(Enum.map(loaded.modular_sets, & &1.id)) == Enum.sort([m1.id, m2.id])

      Games.set_scenario_modular_sets!(s, %{modular_sets: [m2.id]}, actor: owner)
      loaded = Ash.load!(s, [:modular_sets], authorize?: false)
      assert Enum.map(loaded.modular_sets, & &1.id) == [m2.id]

      assert :ok = Games.destroy_scenario(s, actor: owner)
      assert {:error, _} = Games.get_scenario(s.id)
    end

    test "a non-owner is forbidden" do
      s = build!(user_fixture())
      other = user_fixture()

      assert {:error, %Ash.Error.Forbidden{}} =
               Games.rename_scenario(s, %{name: "X"}, actor: other)

      assert {:error, %Ash.Error.Forbidden{}} =
               Games.set_scenario_modular_sets(s, %{modular_sets: []}, actor: other)

      assert {:error, %Ash.Error.Forbidden{}} = Games.destroy_scenario(s, actor: other)
    end

    test "official rows are forbidden to non-admins" do
      official =
        Games.create_scenario!(%{name: "Off", villain_set_id: villain_set!().id},
          authorize?: false
        )

      user = user_fixture()

      assert {:error, %Ash.Error.Forbidden{}} =
               Games.rename_scenario(official, %{name: "X"}, actor: user)

      assert {:error, %Ash.Error.Forbidden{}} = Games.destroy_scenario(official, actor: user)
      assert Ash.load!(official, :official, authorize?: false).official == true

      assert {:ok, %{name: "Admin"}} =
               Games.rename_scenario(official, %{name: "Admin"}, actor: admin_user_fixture())
    end

    test "non-modular and unknown set ids are rejected" do
      owner = user_fixture()
      s = build!(owner)
      m = create(Sanctum.Catalog.CardSet, action: :upsert)
      Games.set_scenario_modular_sets!(s, %{modular_sets: [m.id]}, actor: owner)

      for bad <- [villain_set!().id, Ash.UUID.generate()] do
        assert {:error, %Ash.Error.Invalid{errors: errors}} =
                 Games.set_scenario_modular_sets(s, %{modular_sets: [bad]}, actor: owner)

        assert Enum.any?(errors, &(Map.get(&1, :field) == :modular_sets))
      end

      loaded = Ash.load!(s, :modular_sets, authorize?: false)
      assert Enum.map(loaded.modular_sets, & &1.id) == [m.id]
    end
  end
end
