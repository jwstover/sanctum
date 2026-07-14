defmodule SanctumWeb.DeckLive.IndexTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.Factory

  # Builds a valid deck (hero with both hero + alter-ego sides on one card).
  defp make_deck(title, set, base_code, hero_name, aspects) do
    card =
      create(Sanctum.Games.Card, attrs: %{base_code: base_code, code: base_code <> "a", set: set})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: card.id,
        name: hero_name,
        type: :hero,
        code: base_code <> "a",
        side_identifier: "A",
        is_primary_side: true
      }
    )

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: card.id,
        name: hero_name <> " (alter-ego)",
        type: :alter_ego,
        code: base_code <> "b",
        side_identifier: "B",
        is_primary_side: false
      }
    )

    {:ok, hero} =
      Sanctum.Heroes.find_or_create_hero(%{
        hero_name: hero_name,
        alter_ego_name: hero_name <> " (alter-ego)",
        set: set,
        base_code: base_code,
        card_id: card.id
      })

    {:ok, deck} =
      Sanctum.Decks.Deck
      |> Ash.Changeset.for_create(:create, %{
        title: title,
        hero_id: hero.id,
        aspects: aspects,
        source: :native
      })
      |> Ash.create()

    deck
  end

  test "an anonymous visitor can browse decks", %{conn: conn} do
    make_deck("Web Warrior", "spider_man", "90001", "Spider-Man", [:justice])
    make_deck("Cosmic Blast", "captain_marvel", "90002", "Captain Marvel", [:aggression])

    {:ok, _view, html} = live(conn, ~p"/decks")

    assert html =~ "Browse Decks"
    assert html =~ "Web Warrior"
    assert html =~ "Cosmic Blast"
  end

  test "search narrows the feed", %{conn: conn} do
    make_deck("Web Warrior", "spider_man", "90001", "Spider-Man", [:justice])
    make_deck("Cosmic Blast", "captain_marvel", "90002", "Captain Marvel", [:aggression])

    {:ok, view, _html} = live(conn, ~p"/decks")

    html =
      view
      |> form("form[phx-change=search]", %{query: "cosmic"})
      |> render_change()

    assert html =~ "Cosmic Blast"
    refute html =~ "Web Warrior"
  end
end
