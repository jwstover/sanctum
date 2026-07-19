defmodule Sanctum.Search.ValuesTest do
  @moduledoc """
  Data-driven autocomplete values end-to-end: DB → Values loaders →
  ValueCache → Suggest items (with quoting for multi-word values).
  """

  # The value cache is node-global, so these tests can't run concurrently
  # with each other (each resets the cache against its own sandbox data).
  use Sanctum.DataCase, async: false

  import Sanctum.Factory

  alias Sanctum.Games.{Card, CardSide}
  alias Sanctum.Search.{CardFields, DeckFields, Suggest, ValueCache, Values}

  setup do
    ValueCache.reset()
    on_exit(&ValueCache.reset/0)
  end

  defp insert_side(attrs) do
    card = create(Card, attrs: Map.take(attrs, [:set, :pack]))

    base = %{
      card_id: card.id,
      code: Faker.Util.format("%6da"),
      side_identifier: "A",
      is_primary_side: true
    }

    CardSide
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(card_side_factory(), Map.merge(base, Map.drop(attrs, [:set, :pack])))
    )
    |> Ash.create!(authorize?: false)
  end

  test "traits/sets/packs come from the catalog, deduplicated" do
    insert_side(%{traits: ["Accuser Corps", "Avenger"], set: "core", pack: "core"})
    insert_side(%{traits: ["Avenger"], set: "spider_man", pack: "core"})

    assert "Accuser Corps" in Values.traits()
    assert Enum.count(Values.traits(), &(&1 == "Avenger")) == 1
    assert "spider_man" in Values.sets()
    assert Values.packs() == ["core"]
  end

  test "values are served from memory after first load" do
    insert_side(%{traits: ["Avenger"]})
    assert "Avenger" in Values.traits()

    # Remove the underlying rows; the cached list must still answer.
    Sanctum.Repo.query!("DELETE FROM card_sides")
    assert "Avenger" in Values.traits()
  end

  test "trait suggestions complete from the catalog" do
    insert_side(%{traits: ["Avenger", "Accuser Corps"]})

    result = Suggest.suggest("trait:a", 7, CardFields)
    labels = Enum.map(result.items, & &1.label)
    assert "Avenger" in labels
    assert "Accuser Corps" in labels
  end

  test "multi-word values insert as quoted phrases" do
    insert_side(%{traits: ["Accuser Corps"]})

    result = Suggest.suggest("trait:accuser", 13, CardFields)
    assert [%{label: "Accuser Corps", insert: ~s("Accuser Corps")}] = result.items
  end

  test "hero suggestions complete hero and alter-ego names" do
    card = create(Card, attrs: %{set: "black_widow"})

    hero =
      Sanctum.Heroes.Hero
      |> Ash.Changeset.for_create(:create, %{
        hero_name: "Black Widow",
        alter_ego_name: "Natasha Romanoff",
        set: "black_widow",
        base_code: "07001",
        card_id: card.id
      })
      |> Ash.create!(authorize?: false)

    assert hero.hero_name == "Black Widow"

    result = Suggest.suggest("hero:black", 10, DeckFields)
    assert [%{label: "Black Widow", insert: ~s("Black Widow")}] = result.items

    result2 = Suggest.suggest("hero:nat", 8, DeckFields)
    assert [%{label: "Natasha Romanoff"}] = result2.items
  end

  test "same-named heroes suggest with their alter ego appended" do
    for {alter_ego, set, base_code} <- [
          {"T'Challa", "black_panther", "01040"},
          {"Shuri", "black_panther_shuri", "51001"}
        ] do
      card = create(Card, attrs: %{set: set})

      Sanctum.Heroes.Hero
      |> Ash.Changeset.for_create(:create, %{
        hero_name: "Black Panther",
        alter_ego_name: alter_ego,
        set: set,
        base_code: base_code,
        card_id: card.id
      })
      |> Ash.create!(authorize?: false)
    end

    result = Suggest.suggest("hero:black", 10, DeckFields)
    labels = Enum.map(result.items, & &1.label)
    assert "Black Panther (Shuri)" in labels
    assert "Black Panther (T'Challa)" in labels
    refute "Black Panther" in labels
  end
end
