defmodule SanctumWeb.DeckLive.BuildTest do
  @moduledoc false

  # Not async: the staples test must upsert the canonical core codes
  # (01088–01090), which card_sync_test also inserts — concurrent sandboxed
  # transactions on the same unique keys block/deadlock (see the
  # collection-tests precedent).
  use SanctumWeb.ConnCase, async: false

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

  defp player_card(name, opts \\ []) do
    card =
      create(Sanctum.Games.Card,
        attrs: %{
          set: Keyword.get(opts, :set, "build_pool"),
          deck_limit: Keyword.get(opts, :deck_limit, 3),
          unique: Keyword.get(opts, :unique, false)
        }
      )

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: card.id,
        name: name,
        type: Keyword.get(opts, :type, :ally),
        ownership: Keyword.get(opts, :ownership, :basic),
        aspect: Keyword.get(opts, :aspect),
        code: card.code,
        side_identifier: "A",
        is_primary_side: true
      }
    )

    card
  end

  defp deck_quantities(deck_id) do
    Sanctum.Decks.DeckCard
    |> Ash.Query.filter(deck_id == ^deck_id)
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.card_id, &1.quantity})
  end

  defp mount_builder(conn, set_prefix) do
    %{hero: hero, signature: signature} = make_hero(set_prefix, "Builder #{set_prefix}")
    user = user_fixture()
    deck = Sanctum.Decks.build_deck!(%{hero_id: hero.id, aspects: [:justice]}, actor: user)

    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/decks/#{deck.id}/build")

    %{lv: lv, deck: deck, user: user, signature: signature}
  end

  test "grid offers player/basic cards and inc persists a row", %{conn: conn} do
    card = player_card("Grid Basic Ally")
    %{lv: lv, deck: deck} = mount_builder(conn, "build_lv_a")

    # Wait out the async first page.
    render_async(lv)
    assert render(lv) =~ "Grid Basic Ally"

    lv
    |> element("#builder-grid button[phx-click='inc'][phx-value-card-id='#{card.id}']")
    |> render_click()

    assert deck_quantities(deck.id)[card.id] == 1
  end

  test "inc then dec to zero deletes the row", %{conn: conn} do
    card = player_card("Transient Ally")
    %{lv: lv, deck: deck} = mount_builder(conn, "build_lv_b")

    render_async(lv)

    lv
    |> element("#builder-grid button[phx-click='inc'][phx-value-card-id='#{card.id}']")
    |> render_click()

    assert deck_quantities(deck.id)[card.id] == 1

    lv
    |> element("#builder-grid button[phx-click='dec'][phx-value-card-id='#{card.id}']")
    |> render_click()

    refute Map.has_key?(deck_quantities(deck.id), card.id)
  end

  test "inc clamps at the card's deck limit", %{conn: conn} do
    card = player_card("Limited Ally", deck_limit: 1)
    %{lv: lv, deck: deck} = mount_builder(conn, "build_lv_c")

    render_async(lv)

    inc = "#builder-grid button[phx-click='inc'][phx-value-card-id='#{card.id}']"
    lv |> element(inc) |> render_click()
    # The + is disabled at max; a forced event must still not exceed it.
    render_click(lv, "inc", %{"card-id" => card.id})

    assert deck_quantities(deck.id)[card.id] == 1
  end

  test "filter sheet changes rewrite the query and narrow the grid", %{conn: conn} do
    player_card("Sheet Ally", type: :ally)
    player_card("Sheet Upgrade", type: :upgrade)
    %{lv: lv} = mount_builder(conn, "build_lv_fs")

    render_async(lv)
    assert render(lv) =~ "Sheet Ally"
    assert render(lv) =~ "Sheet Upgrade"

    lv |> form("#builder-filters-form") |> render_change(%{"type" => ["", "upgrade"]})
    html = render_async(lv)

    assert html =~ "Sheet Upgrade"
    refute html =~ "Sheet Ally"

    # the sheet wrote the clause into the search input's value
    assert has_element?(lv, ~s(#builder-query-input[value="type:upgrade"]))
    # and the typed query direction: checked control reflects it
    assert has_element?(lv, ~s(#builder-filters input[value="upgrade"][checked]))
  end

  test "grid tiles arrive badged with quantities already in the deck", %{conn: conn} do
    card = player_card("Prebadged Ally")
    %{deck: deck, user: user} = mount_builder(conn, "build_lv_pre") |> Map.take([:deck, :user])

    Sanctum.Decks.set_card_quantity(deck.id, card.id, 2, user)

    # A fresh mount must stamp the stream tiles from the persisted deck.
    {:ok, lv, _html} = live(log_in_user(build_conn(), user), ~p"/decks/#{deck.id}/build")
    render_async(lv)

    assert has_element?(
             lv,
             "#builder-grid button[phx-click='dec'][phx-value-card-id='#{card.id}']"
           )
  end

  test "hero signature cards are not offered in the grid", %{conn: conn} do
    %{lv: lv, signature: signature} = mount_builder(conn, "build_lv_d")

    render_async(lv)

    refute has_element?(
             lv,
             "#builder-grid button[phx-click='inc'][phx-value-card-id='#{signature.id}']"
           )
  end

  test "signature quantities cannot be changed through events", %{conn: conn} do
    %{lv: lv, deck: deck, signature: signature} = mount_builder(conn, "build_lv_e")

    render_async(lv)
    render_click(lv, "inc", %{"card-id" => signature.id})

    assert deck_quantities(deck.id)[signature.id] == 2
  end

  test "staples quick-add is idempotent and hardcodes 1x", %{conn: conn} do
    for {code, name} <- [{"01088", "Energy"}, {"01089", "Genius"}, {"01090", "Strength"}] do
      card =
        create(Sanctum.Games.Card,
          attrs: %{base_code: code, code: code, set: "core", deck_limit: 4}
        )

      create(Sanctum.Games.CardSide,
        attrs: %{
          card_id: card.id,
          name: name,
          type: :resource,
          ownership: :basic,
          code: "#{code}s",
          side_identifier: "A",
          is_primary_side: true
        }
      )
    end

    %{lv: lv, deck: deck} = mount_builder(conn, "build_lv_f")
    render_async(lv)

    lv |> element("button[phx-click='add_staples']") |> render_click()

    staple_ids =
      Sanctum.Games.Card
      |> Ash.Query.filter(base_code in ["01088", "01089", "01090"])
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.id)

    quantities = deck_quantities(deck.id)
    assert Enum.all?(staple_ids, &(quantities[&1] == 1))

    # Second tap changes nothing.
    lv |> element("button[phx-click='add_staples']") |> render_click()
    assert deck_quantities(deck.id) == quantities
  end

  test "deck size and issue count render in the bottom bar", %{conn: conn} do
    %{lv: lv} = mount_builder(conn, "build_lv_g")

    render_async(lv)
    html = render(lv)

    # 2x signature seeded → far below 40 → too_few issue present.
    assert html =~ "/ 40–50 cards"
    assert has_element?(lv, "[class*='text-warning']")
  end

  describe "deck panel" do
    test "renames the deck on blur/submit", %{conn: conn} do
      %{lv: lv, deck: deck} = mount_builder(conn, "build_lv_h")
      render_async(lv)

      lv |> form("#rename-desktop", %{title: "Panel Renamed"}) |> render_submit()

      assert Sanctum.Decks.get_deck!(deck.id, authorize?: false).title == "Panel Renamed"
      assert render(lv) =~ "Panel Renamed"
    end

    test "hero signature rows are locked (no steppers)", %{conn: conn} do
      %{lv: lv, signature: signature} = mount_builder(conn, "build_lv_j")
      render_async(lv)

      html = render(lv)
      assert html =~ "#{signature.code}" or html =~ "Signature"
      assert html =~ "hero-lock-closed"
      # No panel stepper targets the signature card.
      refute has_element?(
               lv,
               "[phx-click='dec'][phx-value-card-id='#{signature.id}']"
             )
    end

    test "deleting requires the inline confirm and then navigates away", %{conn: conn} do
      %{lv: lv, deck: deck} = mount_builder(conn, "build_lv_k")
      render_async(lv)

      # First tap only reveals the confirm row.
      lv |> element("button[phx-click='confirm_delete']") |> render_click()
      assert {:ok, _deck} = Sanctum.Decks.get_deck(deck.id, authorize?: false)

      assert {:error, {:live_redirect, %{to: "/decks"}}} =
               lv
               |> element("button[phx-click='delete_deck']")
               |> render_click()

      assert {:error, _not_found} = Sanctum.Decks.get_deck(deck.id, authorize?: false)
    end

    test "description tab edits, previews, and saves the writeup", %{conn: conn} do
      %{lv: lv, deck: deck} = mount_builder(conn, "build_lv_m")
      render_async(lv)

      lv |> element("button[phx-click='set_tab'][phx-value-key='description']") |> render_click()

      lv
      |> form("#description-form", %{description: "**Web-slinging** combos"})
      |> render_change()

      # Preview renders the draft through Writeup (markdown → HTML).
      html =
        lv
        |> element("button[phx-click='set_description_mode'][phx-value-key='preview']")
        |> render_click()

      assert html =~ "<strong>Web-slinging</strong>"

      # Nothing persisted yet.
      assert Sanctum.Decks.get_deck!(deck.id, authorize?: false).description_md == nil

      lv |> element("button[phx-click='save_description']") |> render_click()

      assert Sanctum.Decks.get_deck!(deck.id, authorize?: false).description_md ==
               "**Web-slinging** combos"
    end

    # `{:reply, ...}` payloads aren't inspectable through LiveViewTest, but
    # exercising the handler still covers the browse query and item mapping
    # (a bad filter or missing card load would crash the view).
    test "card_mention event answers the description editor's picker", %{conn: conn} do
      player_card("Web-Shooter")
      %{lv: lv} = mount_builder(conn, "build_lv_n")
      render_async(lv)

      assert render_hook(lv, "card_mention", %{"q" => "web-sho"})
      assert render_hook(lv, "card_mention", %{"q" => "  "})
      assert render_hook(lv, "card_mention", %{"bogus" => true})
    end

    test "card picker searches the catalog and pushes the insert", %{conn: conn} do
      card = player_card("Web-Shooter")
      %{lv: lv} = mount_builder(conn, "build_lv_pick_c")
      render_async(lv)

      lv |> element("button[phx-click='set_tab'][phx-value-key='description']") |> render_click()
      assert has_element?(lv, "[data-md-cmd='bold']")

      render_click(lv, "open_picker", %{"kind" => "card"})
      assert has_element?(lv, "#writeup-picker")

      lv |> form("#writeup-picker-form", %{q: "web-sho"}) |> render_change()
      assert render(lv) =~ "Web-Shooter"

      render_click(lv, "pick", %{"index" => "0"})

      assert_push_event(lv, "writeup:insert", %{text: text})
      assert text == "[Web-Shooter](/card/#{card.base_code})"
      refute has_element?(lv, "#writeup-picker")
    end

    test "icon picker filters glyphs and Enter takes the top result", %{conn: conn} do
      %{lv: lv} = mount_builder(conn, "build_lv_pick_i")
      render_async(lv)

      lv |> element("button[phx-click='set_tab'][phx-value-key='description']") |> render_click()

      # Opening lists every glyph; filtering narrows; submit picks the top.
      render_click(lv, "open_picker", %{"kind" => "icon"})
      assert render(lv) =~ "Acceleration"

      lv |> form("#writeup-picker-form", %{q: "ment"}) |> render_change()
      lv |> form("#writeup-picker-form") |> render_submit()

      assert_push_event(lv, "writeup:insert", %{text: "[mental]"})
      refute has_element?(lv, "#writeup-picker")
    end

    test "escape and out-of-range picks close or no-op safely", %{conn: conn} do
      %{lv: lv} = mount_builder(conn, "build_lv_pick_e")
      render_async(lv)

      lv |> element("button[phx-click='set_tab'][phx-value-key='description']") |> render_click()

      render_click(lv, "open_picker", %{"kind" => "card"})
      render_click(lv, "pick", %{"index" => "5"})
      assert has_element?(lv, "#writeup-picker")

      render_click(lv, "close_picker", %{"key" => "Escape"})
      refute has_element?(lv, "#writeup-picker")
    end

    test "cancel backs out of the delete confirm", %{conn: conn} do
      %{lv: lv, deck: deck} = mount_builder(conn, "build_lv_l")
      render_async(lv)

      lv |> element("button[phx-click='confirm_delete']") |> render_click()
      lv |> element("button[phx-click='cancel_delete']") |> render_click()

      refute has_element?(lv, "button[phx-click='delete_deck']")
      assert {:ok, _deck} = Sanctum.Decks.get_deck(deck.id, authorize?: false)
    end
  end
end
