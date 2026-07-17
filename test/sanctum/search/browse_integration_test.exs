defmodule Sanctum.Search.BrowseIntegrationTest do
  @moduledoc """
  End-to-end: advanced search queries through the real `:browse` read actions
  against Postgres — this is what proves the jsonb stat fragments, trait
  ILIKE ANY, relationship paths, and exists() subqueries actually run.
  """

  use Sanctum.DataCase, async: true

  import Sanctum.Factory

  alias Sanctum.Games.{Card, CardSide}

  defp insert_card(attrs \\ %{}) do
    create(Card, attrs: attrs)
  end

  defp insert_side(attrs) do
    card = insert_card()

    base = %{
      card_id: card.id,
      code: Faker.Util.format("%6da"),
      side_identifier: "A",
      is_primary_side: true
    }

    CardSide
    |> Ash.Changeset.for_create(:create, Map.merge(card_side_factory(), Map.merge(base, attrs)))
    |> Ash.create!(authorize?: false)
  end

  defp browse(query_string) do
    CardSide
    |> Ash.Query.for_read(:browse, %{query: query_string})
    |> Ash.read!(authorize?: false)
  end

  defp browse_names(query_string) do
    query_string |> browse() |> Enum.map(& &1.name) |> Enum.sort()
  end

  describe "card :browse with advanced queries" do
    setup do
      insert_side(%{
        name: "Cheap Ally",
        type: :ally,
        aspect: :aggression,
        ownership: :player,
        cost: 2,
        attack: %{value: 1},
        traits: ["Avenger"],
        text: "When Revealed: draw a card."
      })

      insert_side(%{
        name: "Pricey Ally",
        type: :ally,
        aspect: :aggression,
        ownership: :player,
        cost: 4,
        attack: %{value: 3},
        traits: ["Guardian"],
        text: "Enters play exhausted."
      })

      insert_side(%{
        name: "Justice Event",
        type: :event,
        aspect: :justice,
        ownership: :player,
        cost: 1,
        attack: nil,
        traits: [],
        text: "Remove 2 threat from a scheme."
      })

      :ok
    end

    test "the flagship query" do
      assert browse_names("aspect = aggression AND cost <= 2 AND type = ally") == ["Cheap Ally"]
    end

    test "shorthand form matches" do
      assert browse_names("a:aggression c<=2 t:ally") == ["Cheap Ally"]
    end

    test "bare word still searches names" do
      assert browse_names("pricey") == ["Pricey Ally"]
    end

    test "stat comparison reaches into the jsonb value" do
      assert browse_names("attack>=2") == ["Pricey Ally"]
      # nil stats drop out rather than erroring
      assert browse_names("attack<=1") == ["Cheap Ally"]
    end

    test "trait match is case-insensitive" do
      assert browse_names("trait:avenger") == ["Cheap Ally"]
      assert browse_names("k:AVENGER") == ["Cheap Ally"]
    end

    test "text search" do
      assert browse_names(~s{text:"draw a card"}) == ["Cheap Ally"]
    end

    test "or and negation" do
      assert browse_names("t:event or cost>=4") == ["Justice Event", "Pricey Ally"]
      assert browse_names("t:ally -trait:guardian") == ["Cheap Ally"]
    end

    test "pipe value alternatives" do
      assert browse_names("aspect:justice|aggression cost<=2") == ["Cheap Ally", "Justice Event"]
    end

    test "invalid value on a known field matches nothing" do
      assert browse_names("aspect:agression") == []
    end

    test "unknown field is dropped, rest still filters" do
      assert browse_names("bogus:1 t:event") == ["Justice Event"]
    end

    test "incomplete trailing clause keeps the valid prefix live" do
      assert browse_names("t:ally cost <") == ["Cheap Ally", "Pricey Ally"]
    end

    test "card-level fields via the relationship" do
      assert browse_names("set:core t:ally") == ["Cheap Ally", "Pricey Ally"]
      assert browse_names("set:nonexistent") == []
    end
  end

  describe "deck :browse with advanced queries" do
    test "hero, aspect, and containment queries run" do
      # No decks in the sandbox — just prove the filters execute (no SQL errors).
      for q <- [
            "hero:spider aspect:justice",
            "aspect:basic",
            ~s(card:"boot camp"),
            "cards>=40",
            "source:marvelcdb"
          ] do
        assert Sanctum.Decks.Deck
               |> Ash.Query.for_read(:browse, %{query: q})
               |> Ash.read!(authorize?: false) == []
      end
    end
  end
end
