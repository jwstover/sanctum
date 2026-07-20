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
end
