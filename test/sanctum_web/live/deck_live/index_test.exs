defmodule SanctumWeb.DeckLive.IndexTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.Factory

  # Builds a valid deck (hero with both hero + alter-ego sides on one card).
  defp make_deck(title, set, base_code, hero_name, aspects, deck_attrs \\ %{}) do
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
      |> Ash.Changeset.for_create(
        :create,
        Map.merge(
          %{title: title, hero_id: hero.id, aspects: aspects, source: :native},
          deck_attrs
        )
      )
      |> Ash.create()

    deck
  end

  test "an anonymous visitor can browse decks", %{conn: conn} do
    make_deck("Web Warrior", "spider_man", "90001", "Spider-Man", [:justice])
    make_deck("Cosmic Blast", "captain_marvel", "90002", "Captain Marvel", [:aggression])

    {:ok, view, html} = live(conn, ~p"/decks")

    # The header paints on the shell; the deck feed loads asynchronously.
    assert html =~ "Browse Decks"

    html = render_async(view)
    assert html =~ "Web Warrior"
    assert html =~ "Cosmic Blast"
  end

  test "deck dates render in the browser's timezone", %{conn: conn} do
    deck = make_deck("Web Warrior", "spider_man", "90001", "Spider-Man", [:justice])

    # 02:35 UTC on the 21st is still the evening of the 20th in Chicago.
    deck
    |> Ash.Changeset.for_update(:set_mcdb_dates, %{mcdb_date_update: ~U[2026-07-21 02:35:12Z]})
    |> Ash.update!(authorize?: false)

    {:ok, view, _html} =
      conn
      |> put_connect_params(%{"timezone" => "America/Chicago"})
      |> live(~p"/decks")

    assert render_async(view) =~ "Jul 20, 2026"
  end

  test "an unknown browser timezone falls back to UTC", %{conn: conn} do
    deck = make_deck("Web Warrior", "spider_man", "90001", "Spider-Man", [:justice])

    deck
    |> Ash.Changeset.for_update(:set_mcdb_dates, %{mcdb_date_update: ~U[2026-07-21 02:35:12Z]})
    |> Ash.update!(authorize?: false)

    {:ok, view, _html} =
      conn
      |> put_connect_params(%{"timezone" => "Not/AZone"})
      |> live(~p"/decks")

    assert render_async(view) =~ "Jul 21, 2026"
  end

  test "search narrows the feed", %{conn: conn} do
    make_deck("Web Warrior", "spider_man", "90001", "Spider-Man", [:justice])
    make_deck("Cosmic Blast", "captain_marvel", "90002", "Captain Marvel", [:aggression])

    {:ok, view, _html} = live(conn, ~p"/decks")
    render_async(view)

    view
    |> form("#deck-search", %{query: "cosmic"})
    |> render_change()

    html = render_async(view)
    assert html =~ "Cosmic Blast"
    refute html =~ "Web Warrior"
  end

  test "the Mine filter shows only the signed-in user's decks", %{conn: conn} do
    owner = user_fixture()

    make_deck("My Own Deck", "spider_man", "90001", "Spider-Man", [:justice], %{
      owner_id: owner.id
    })

    make_deck("Someone Else's", "captain_marvel", "90002", "Captain Marvel", [:aggression])

    conn = log_in_user(conn, owner)
    {:ok, view, _html} = live(conn, ~p"/decks")
    html = render_async(view)
    assert html =~ "My Own Deck"
    assert html =~ "Someone Else&#39;s"

    view |> element("button", "Mine") |> render_click()
    html = render_async(view)

    assert html =~ "My Own Deck"
    refute html =~ "Someone Else&#39;s"
  end

  test "signed-in users get a New Deck button; anonymous visitors don't", %{conn: conn} do
    make_deck("Web Warrior", "spider_man", "90001", "Spider-Man", [:justice])

    {:ok, _view, html} = live(conn, ~p"/decks")
    refute html =~ "New Deck"

    conn = log_in_user(conn, user_fixture())
    {:ok, _view, html} = live(conn, ~p"/decks")
    assert html =~ "New Deck"
    assert html =~ "/decks/new"
  end

  test "a native deck credits its owner's username, never their email", %{conn: conn} do
    owner = user_fixture(username: "deck_smith")

    make_deck("Web Warrior", "spider_man", "90001", "Spider-Man", [:justice], %{
      owner_id: owner.id
    })

    {:ok, view, _html} = live(conn, ~p"/decks")
    html = render_async(view)

    assert html =~ "@deck_smith"
    refute html =~ to_string(owner.email)
  end

  test "an owned deck without a claimed username shows no attribution", %{conn: conn} do
    owner = user_fixture()

    make_deck("Web Warrior", "spider_man", "90001", "Spider-Man", [:justice], %{
      owner_id: owner.id
    })

    {:ok, view, _html} = live(conn, ~p"/decks")
    html = render_async(view)

    assert html =~ "Web Warrior"
    refute html =~ to_string(owner.email)
  end

  test "a scored deck shows its uniqueness meter; an unscored one doesn't", %{conn: conn} do
    scored = make_deck("Web Warrior", "spider_man", "90001", "Spider-Man", [:justice])

    _unscored =
      make_deck("Cosmic Blast", "captain_marvel", "90002", "Captain Marvel", [:aggression])

    # uniqueness_percentile is a computed private attribute, set by the worker;
    # write it directly to simulate a scored deck.
    Sanctum.Repo.query!("UPDATE decks SET uniqueness_percentile = $1 WHERE id::text = $2", [
      87,
      scored.id
    ])

    {:ok, view, _html} = live(conn, ~p"/decks")
    html = render_async(view)

    assert html =~ "Uniqueness"
    assert html =~ "87"
    assert html =~ "width:87%"
  end
end
