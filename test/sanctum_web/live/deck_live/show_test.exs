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

    # The deck detail loads asynchronously after mount; await it.
    {:ok, view, _html} = live(conn, ~p"/decks/#{deck.id}")
    html = render_async(view)

    assert html =~ "Web Warrior"
    assert html =~ "Spider-Man"
    assert html =~ "In This Deck"
    assert html =~ "Allies"
    assert html =~ "Thwart twice"
  end

  describe "edit button" do
    defp claim_deck(deck, owner) do
      deck
      |> Ash.Changeset.for_update(:update, %{owner_id: owner.id})
      |> Ash.update!(authorize?: false)
    end

    test "the owner of a native deck sees Edit Deck", %{conn: conn} do
      owner = Sanctum.AccountsFixtures.user_fixture()
      deck = claim_deck(make_deck_with_card(), owner)

      {:ok, view, _html} = live(log_in_user(conn, owner), ~p"/decks/#{deck.id}")
      html = render_async(view)

      assert html =~ "Edit Deck"
      assert html =~ "/decks/#{deck.id}/build"
    end

    test "non-owners and anonymous visitors see no Edit Deck", %{conn: conn} do
      owner = Sanctum.AccountsFixtures.user_fixture()
      deck = claim_deck(make_deck_with_card(), owner)

      {:ok, view, _html} = live(conn, ~p"/decks/#{deck.id}")
      refute render_async(view) =~ "Edit Deck"

      other = Sanctum.AccountsFixtures.user_fixture()
      {:ok, view, _html} = live(log_in_user(conn, other), ~p"/decks/#{deck.id}")
      refute render_async(view) =~ "Edit Deck"
    end

    test "imported decks show no Edit Deck even for their owner", %{conn: conn} do
      owner = Sanctum.AccountsFixtures.user_fixture()

      deck =
        make_deck_with_card()
        |> Ash.Changeset.for_update(
          :update,
          %{owner_id: owner.id, source: :marvelcdb, mcdb_id: "999999", mcdb_type: :decklist}
        )
        |> Ash.update!(authorize?: false)

      {:ok, view, _html} = live(log_in_user(conn, owner), ~p"/decks/#{deck.id}")
      refute render_async(view) =~ "Edit Deck"
    end
  end

  test "a signed-in user sees collection status on the card list", %{conn: conn} do
    deck = make_deck_with_card()
    user = Sanctum.AccountsFixtures.user_fixture()

    # Own the ally (2 copies) via a card override — fully owned decks show
    # the summary but no missing-card marks.
    ally = Ash.get!(Sanctum.Games.Card, %{base_code: "90051"}, authorize?: false)
    Sanctum.Collections.set_card_status!(ally.id, :owned, actor: user)

    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/decks/#{deck.id}")
    html = render_async(view)

    assert html =~ "you own 2 / 2"
    refute html =~ "Not in your collection"
  end

  test "a signed-in user sees unowned cards flagged on the card list", %{conn: conn} do
    deck = make_deck_with_card()
    user = Sanctum.AccountsFixtures.user_fixture()

    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/decks/#{deck.id}")
    html = render_async(view)

    assert html =~ "you own 0 / 2"
    assert html =~ "Not in your collection"
  end

  test "anonymous visitors see no collection summary", %{conn: conn} do
    deck = make_deck_with_card()

    {:ok, view, _html} = live(conn, ~p"/decks/#{deck.id}")
    html = render_async(view)

    refute html =~ "you own"
    refute html =~ "Not in your collection"
  end

  test "restore-scroll confirms once the deck content has loaded", %{conn: conn} do
    deck = make_deck_with_card()

    {:ok, view, _html} = live(conn, ~p"/decks/#{deck.id}")

    render_hook(view, "restore-scroll", %{"offset" => 0})
    render_async(view)

    assert_push_event(view, "sanctum:scroll-restore", %{})
  end

  test "a scored deck shows its uniqueness meter", %{conn: conn} do
    deck = make_deck_with_card()

    # uniqueness_percentile is a computed private attribute; write it directly.
    Sanctum.Repo.query!("UPDATE decks SET uniqueness_percentile = $1 WHERE id::text = $2", [
      92,
      deck.id
    ])

    {:ok, view, _html} = live(conn, ~p"/decks/#{deck.id}")
    html = render_async(view)

    assert html =~ "Uniqueness"
    assert html =~ "92"
    assert html =~ "width:92%"
  end

  test "the detail page lists similar decks of the same hero", %{conn: conn} do
    hero = make_hero("Spider-Man", "spider_man", "91000")
    ally = make_ally("Aunt May", "91010")

    deck_a = deck_with_hero("Amazing Build", hero, [ally])
    _deck_b = deck_with_hero("Spectacular Build", hero, [ally])

    {:ok, view, _html} = live(conn, ~p"/decks/#{deck_a.id}")
    html = render_async(view)

    assert html =~ "Similar Decks"
    assert html =~ "Spectacular Build"
    # Both share their only chosen card → 100% match.
    assert html =~ "100%"
  end

  defp make_hero(name, set, base_code) do
    card =
      create(Sanctum.Games.Card, attrs: %{base_code: base_code, code: base_code <> "a", set: set})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: card.id,
        name: name,
        type: :hero,
        code: base_code <> "a",
        side_identifier: "A",
        is_primary_side: true
      }
    )

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: card.id,
        name: name <> " (alter-ego)",
        type: :alter_ego,
        code: base_code <> "b",
        side_identifier: "B",
        is_primary_side: false
      }
    )

    {:ok, hero} =
      Sanctum.Heroes.find_or_create_hero(%{
        hero_name: name,
        alter_ego_name: name <> " (alter-ego)",
        set: set,
        base_code: base_code,
        card_id: card.id
      })

    hero
  end

  defp make_ally(name, base_code) do
    card = create(Sanctum.Games.Card, attrs: %{base_code: base_code, code: base_code <> "a"})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: card.id,
        name: name,
        type: :ally,
        aspect: :justice,
        cost: 1,
        code: base_code <> "a",
        side_identifier: "A",
        is_primary_side: true
      }
    )

    card
  end

  defp deck_with_hero(title, hero, cards) do
    Sanctum.Decks.Deck
    |> Ash.Changeset.for_create(:create_with_cards, %{
      title: title,
      hero_id: hero.id,
      aspects: [:justice],
      source: :native,
      slots: Enum.map(cards, &%{card_id: &1.id, quantity: 1})
    })
    |> Ash.create!(authorize?: false)
  end
end
