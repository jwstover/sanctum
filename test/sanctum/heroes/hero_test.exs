defmodule Sanctum.Heroes.HeroTest do
  use Sanctum.DataCase, async: true

  alias Sanctum.Heroes

  describe "hero_side and alter_ego_side relationships" do
    setup do
      set_name = "test_hero_#{:rand.uniform(100_000)}"
      base_code = "hero#{:rand.uniform(100_000)}"

      {:ok, card} =
        Sanctum.Games.Card
        |> Ash.Changeset.for_create(:create, %{
          base_code: base_code,
          code: base_code,
          set: set_name,
          pack: set_name,
          is_multi_sided: true
        })
        |> Ash.create()

      {:ok, hero_side} =
        Sanctum.Games.CardSide
        |> Ash.Changeset.for_create(:create, %{
          card_id: card.id,
          name: "Test Hero",
          code: "#{base_code}a",
          side_identifier: "A",
          is_primary_side: true,
          type: :hero,
          health: 11,
          hand_size: 5,
          attack: 2,
          thwart: 2,
          defense: 1
        })
        |> Ash.create()

      {:ok, alter_ego_side} =
        Sanctum.Games.CardSide
        |> Ash.Changeset.for_create(:create, %{
          card_id: card.id,
          name: "Test Alter Ego",
          code: "#{base_code}b",
          side_identifier: "B",
          is_primary_side: false,
          type: :alter_ego,
          health: 11,
          hand_size: 6,
          recover: 3
        })
        |> Ash.create()

      {:ok, hero} =
        Heroes.find_or_create_hero(%{
          hero_name: "Test Hero",
          alter_ego_name: "Test Alter Ego",
          set: set_name,
          base_code: base_code,
          card_id: card.id
        })

      %{
        hero: hero,
        card: card,
        hero_side: hero_side,
        alter_ego_side: alter_ego_side
      }
    end

    test "card loads the backing Card via the card_id foreign key", %{hero: hero, card: card} do
      loaded = Ash.load!(hero, [:card])

      assert hero.card_id == card.id
      assert %Sanctum.Games.Card{} = loaded.card
      assert loaded.card.id == card.id
    end

    test "hero_side loads the single hero card side", %{hero: hero, hero_side: hero_side} do
      loaded = Ash.load!(hero, [:hero_side])

      refute is_list(loaded.hero_side)
      refute is_nil(loaded.hero_side)
      assert %Sanctum.Games.CardSide{} = loaded.hero_side
      assert loaded.hero_side.id == hero_side.id
      assert loaded.hero_side.type == :hero
      assert loaded.hero_side.health == 11
    end

    test "alter_ego_side loads the single alter_ego card side", %{
      hero: hero,
      alter_ego_side: alter_ego_side
    } do
      loaded = Ash.load!(hero, [:alter_ego_side])

      refute is_list(loaded.alter_ego_side)
      refute is_nil(loaded.alter_ego_side)
      assert %Sanctum.Games.CardSide{} = loaded.alter_ego_side
      assert loaded.alter_ego_side.id == alter_ego_side.id
      assert loaded.alter_ego_side.type == :alter_ego
    end

    test "loads both sides distinctly at once", %{
      hero: hero,
      hero_side: hero_side,
      alter_ego_side: alter_ego_side
    } do
      loaded = Ash.load!(hero, [:hero_side, :alter_ego_side])

      assert loaded.hero_side.id == hero_side.id
      assert loaded.alter_ego_side.id == alter_ego_side.id
      assert loaded.hero_side.id != loaded.alter_ego_side.id
    end
  end
end
