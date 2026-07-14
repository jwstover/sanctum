defmodule SanctumWeb.DeckLive.ShowTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.Factory

  defp make_deck_with_card do
    hero_card =
      create(Sanctum.Games.Card, attrs: %{base_code: "90050", code: "90050a", set: "spider_man"})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: hero_card.id,
        name: "Spider-Man",
        type: :hero,
        code: "90050a",
        side_identifier: "A",
        is_primary_side: true
      }
    )

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: hero_card.id,
        name: "Peter Parker",
        type: :alter_ego,
        code: "90050b",
        side_identifier: "B",
        is_primary_side: false
      }
    )

    {:ok, hero} =
      Sanctum.Heroes.find_or_create_hero(%{
        hero_name: "Spider-Man",
        alter_ego_name: "Peter Parker",
        set: "spider_man",
        base_code: "90050",
        card_id: hero_card.id
      })

    {:ok, deck} =
      Sanctum.Decks.Deck
      |> Ash.Changeset.for_create(:create, %{
        title: "Web Warrior",
        hero_id: hero.id,
        aspects: [:justice],
        source: :native,
        description_md: "Thwart twice, apologise never."
      })
      |> Ash.create()

    ally = create(Sanctum.Games.Card, attrs: %{base_code: "90051", code: "90051a"})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: ally.id,
        name: "Beat Cop",
        type: :ally,
        aspect: :justice,
        cost: 3,
        code: "90051a",
        side_identifier: "A",
        is_primary_side: true
      }
    )

    Sanctum.Decks.DeckCard
    |> Ash.Changeset.for_create(:create, %{deck_id: deck.id, card_id: ally.id, quantity: 2})
    |> Ash.create!(authorize?: false)

    deck
  end

  test "an anonymous visitor can view a deck's cover, notes, and card list", %{conn: conn} do
    deck = make_deck_with_card()

    {:ok, _view, html} = live(conn, ~p"/decks/#{deck.id}")

    assert html =~ "Web Warrior"
    assert html =~ "Spider-Man"
    assert html =~ "In This Deck"
    assert html =~ "Allies"
    assert html =~ "Thwart twice"
  end
end
