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

  describe "card :browse with owned:" do
    defp browse_names_as(query_string, actor) do
      CardSide
      |> Ash.Query.for_read(:browse, %{query: query_string}, actor: actor)
      |> Ash.read!(actor: actor)
      |> Enum.map(& &1.name)
      |> Enum.sort()
    end

    setup do
      user = Sanctum.AccountsFixtures.user_fixture()
      pack = create(Sanctum.Catalog.Pack, action: :upsert_from_marvelcdb)

      owned_card = insert_card(%{pack_id: pack.id})

      CardSide
      |> Ash.Changeset.for_create(
        :create,
        Map.merge(card_side_factory(), %{
          card_id: owned_card.id,
          code: Faker.Util.format("%6da"),
          name: "Owned Ally",
          type: :ally
        })
      )
      |> Ash.create!(authorize?: false)

      insert_side(%{name: "Unowned Ally", type: :ally})

      Sanctum.Collections.add_pack!(pack.id, actor: user)

      %{user: user}
    end

    test "owned:true returns only the actor's collection", %{user: user} do
      assert browse_names_as("owned:true", user) == ["Owned Ally"]
      assert browse_names_as("t:ally owned:false", user) == ["Unowned Ally"]
      assert browse_names_as("-owned:true t:ally", user) == ["Unowned Ally"]
    end

    test "owned:true is empty for anonymous browsing" do
      assert browse_names_as("owned:true", nil) == []
      assert "Owned Ally" in browse_names_as("owned:false", nil)
    end
  end

  describe "deck :browse with advanced queries" do
    defp insert_hero_deck(hero_name, alter_ego, set, base_code) do
      card = insert_card(%{base_code: base_code, set: set})

      for {name, type, side_id} <- [{hero_name, :hero, "A"}, {alter_ego, :alter_ego, "B"}] do
        CardSide
        |> Ash.Changeset.for_create(
          :create,
          Map.merge(card_side_factory(), %{
            card_id: card.id,
            code: Faker.Util.format("%6da"),
            name: name,
            type: type,
            side_identifier: side_id,
            is_primary_side: side_id == "A"
          })
        )
        |> Ash.create!(authorize?: false)
      end

      {:ok, hero} =
        Sanctum.Heroes.find_or_create_hero(%{
          hero_name: hero_name,
          alter_ego_name: alter_ego,
          set: set,
          base_code: base_code,
          card_id: card.id
        })

      Sanctum.Decks.Deck
      |> Ash.Changeset.for_create(:create, %{title: "#{alter_ego} deck", hero_id: hero.id})
      |> Ash.create!(authorize?: false)
    end

    defp deck_titles(query_string) do
      Sanctum.Decks.Deck
      |> Ash.Query.for_read(:browse, %{query: query_string})
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.title)
      |> Enum.sort()
    end

    test "hero search by display name disambiguates same-named heroes" do
      insert_hero_deck("Black Panther", "T'Challa", "black_panther", "01040")
      insert_hero_deck("Black Panther", "Shuri", "black_panther_shuri", "51001")

      assert deck_titles(~s{hero:"black panther (shuri)"}) == ["Shuri deck"]
      assert deck_titles(~s{hero:"black panther (t'challa)"}) == ["T'Challa deck"]
      assert deck_titles("hero:shuri") == ["Shuri deck"]
      # The bare hero name still matches both.
      assert deck_titles(~s{hero:"black panther"}) == ["Shuri deck", "T'Challa deck"]
    end

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
