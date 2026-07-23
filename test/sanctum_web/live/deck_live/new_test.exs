defmodule SanctumWeb.DeckLive.NewTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.AccountsFixtures
  import Sanctum.Factory

  require Ash.Query

  defp make_hero(set, name) do
    hero_card = create(Sanctum.Games.Card, attrs: %{base_code: "#{set}x", set: set})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: hero_card.id,
        name: name,
        type: :hero,
        ownership: :hero,
        code: "#{hero_card.code}a",
        side_identifier: "A",
        is_primary_side: true
      }
    )

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: hero_card.id,
        name: "#{name} Alter",
        type: :alter_ego,
        ownership: :hero,
        code: "#{hero_card.code}b",
        side_identifier: "B",
        is_primary_side: false
      }
    )

    signature = create(Sanctum.Games.Card, attrs: %{set: set, deck_limit: 2})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: signature.id,
        name: "#{name} Signature",
        type: :event,
        ownership: :hero,
        code: signature.code,
        side_identifier: "A",
        is_primary_side: true
      }
    )

    {:ok, hero} =
      Sanctum.Heroes.find_or_create_hero(%{
        hero_name: name,
        alter_ego_name: "#{name} Alter",
        set: set,
        base_code: hero_card.base_code,
        card_id: hero_card.id
      })

    %{hero: hero, signature: signature}
  end

  test "anonymous visitors are redirected to sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/decks/new")
  end

  test "lists buildable heroes", %{conn: conn} do
    make_hero("new_deck_hero_a", "Grid Hero A")
    conn = log_in_user(conn, user_fixture())

    {:ok, _lv, html} = live(conn, ~p"/decks/new")

    assert html =~ "New Deck"
    assert html =~ "Grid Hero A"
  end

  test "heroes without an alter-ego side are not offered", %{conn: conn} do
    # Hero-side-only identity (SP//dr style) fails ValidateHero on :build.
    lone_card = create(Sanctum.Games.Card, attrs: %{base_code: "new_lonex", set: "new_lone"})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: lone_card.id,
        name: "Loner Hero",
        type: :hero,
        ownership: :hero,
        code: "#{lone_card.code}a",
        side_identifier: "A",
        is_primary_side: true
      }
    )

    {:ok, _hero} =
      Sanctum.Heroes.find_or_create_hero(%{
        hero_name: "Loner Hero",
        alter_ego_name: nil,
        set: "new_lone",
        base_code: lone_card.base_code,
        card_id: lone_card.id
      })

    conn = log_in_user(conn, user_fixture())
    {:ok, _lv, html} = live(conn, ~p"/decks/new")

    refute html =~ "Loner Hero"
  end

  test "selecting a hero and creating lands in the builder with signature cards", %{conn: conn} do
    %{hero: hero, signature: signature} = make_hero("new_deck_hero_b", "Grid Hero B")
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/decks/new")

    lv |> element("button[phx-value-id='#{hero.id}']") |> render_click()
    lv |> element("#deck-confirm .filter_pill, #deck-confirm button", "Justice") |> render_click()

    assert {:error, {:live_redirect, %{to: to}}} =
             lv |> form("#deck-confirm", %{title: "Test Build"}) |> render_submit()

    assert to =~ ~r{^/decks/.+/build$}

    deck_id = to |> String.split("/") |> Enum.at(2)
    deck = Sanctum.Decks.get_deck!(deck_id, load: [:deck_cards], authorize?: false)

    assert deck.title == "Test Build"
    assert deck.owner_id == user.id
    assert deck.aspects == [:justice]
    assert Enum.map(deck.deck_cards, & &1.card_id) == [signature.id]
    assert hd(deck.deck_cards).quantity == 2
  end

  test "the builder page mounts for the owner", %{conn: conn} do
    %{hero: hero} = make_hero("new_deck_hero_c", "Grid Hero C")
    user = user_fixture()
    deck = Sanctum.Decks.build_deck!(%{hero_id: hero.id}, actor: user)

    conn = log_in_user(conn, user)
    {:ok, _lv, html} = live(conn, ~p"/decks/#{deck.id}/build")

    assert html =~ deck.title
  end

  test "the builder redirects non-owners of a published deck to the deck page", %{conn: conn} do
    %{hero: hero} = make_hero("new_deck_hero_d", "Grid Hero D")
    owner = user_fixture()
    deck = Sanctum.Decks.build_deck!(%{hero_id: hero.id}, actor: owner)
    deck = Sanctum.Decks.finalize_deck!(deck, actor: owner)
    deck = Sanctum.Decks.publish_deck!(deck, actor: owner)

    conn = log_in_user(conn, user_fixture())

    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/decks/#{deck.id}/build")
    assert to == "/decks/#{deck.id}"
  end

  test "a private deck's builder is not found for non-owners", %{conn: conn} do
    %{hero: hero} = make_hero("new_deck_hero_e", "Grid Hero E")
    owner = user_fixture()
    deck = Sanctum.Decks.build_deck!(%{hero_id: hero.id}, actor: owner)

    conn = log_in_user(conn, user_fixture())

    # The visibility policy filters the deck out entirely — a private deck
    # reads as nonexistent, not merely locked.
    assert {:error, {:live_redirect, %{to: "/decks"}}} = live(conn, ~p"/decks/#{deck.id}/build")
  end
end
