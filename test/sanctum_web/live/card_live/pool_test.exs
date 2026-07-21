defmodule SanctumWeb.CardLive.PoolTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.Factory

  defp make_card(attrs) do
    code = Map.fetch!(attrs, :code)

    card =
      create(Sanctum.Games.Card,
        attrs: %{base_code: String.slice(code, 0..4), code: code, pack: "core"}
      )

    create(
      Sanctum.Games.CardSide,
      attrs:
        Map.merge(
          %{
            card_id: card.id,
            side_identifier: "A",
            is_primary_side: true
          },
          attrs
        )
    )

    card
  end

  test "static (disconnected) render paints the shell without blocking on card data",
       %{conn: conn} do
    make_card(%{code: "01001a", name: "Spider-Man", type: :hero})

    # The plain HTTP render must not run the browse query — it shows the shell
    # and a loading state, and carries no card tiles.
    html = conn |> get(~p"/cards") |> html_response(200)

    assert html =~ "Card Pool"
    assert html =~ "Loading…"
    refute html =~ "Spider-Man"
  end

  test "connected render loads cards asynchronously and reports the total", %{conn: conn} do
    make_card(%{code: "01001a", name: "Spider-Man", type: :hero})
    make_card(%{code: "01002a", name: "Iron Man", type: :hero})

    {:ok, lv, _html} = live(conn, ~p"/cards")

    html = render_async(lv)

    assert html =~ "Spider-Man"
    assert html =~ "Iron Man"
    assert html =~ "2 </span>" or html =~ "2 <span" or html =~ "/ 2 cards"
  end

  test "search filter narrows the results asynchronously", %{conn: conn} do
    make_card(%{code: "01001a", name: "Spider-Man", type: :hero})
    make_card(%{code: "01002a", name: "Iron Man", type: :hero})

    {:ok, lv, _html} = live(conn, ~p"/cards")
    render_async(lv)

    lv |> form("#card-search", query: "spider") |> render_change()

    html = render_async(lv)

    assert html =~ "Spider-Man"
    refute html =~ "Iron Man"
  end

  test "search patches the query into the URL", %{conn: conn} do
    make_card(%{code: "01001a", name: "Spider-Man", type: :hero})

    {:ok, lv, _html} = live(conn, ~p"/cards")
    render_async(lv)

    lv |> form("#card-search", query: "spider") |> render_change()

    assert_patch(lv, ~p"/cards?query=spider")
  end

  test "mounting with filter params applies them", %{conn: conn} do
    make_card(%{code: "01001a", name: "Spider-Man", type: :hero})
    make_card(%{code: "01003a", name: "Web Kick", type: :event, ownership: :hero})

    {:ok, lv, _html} = live(conn, ~p"/cards?query=web")

    html = render_async(lv)

    assert html =~ "Web Kick"
    refute html =~ "Spider-Man"
  end

  test "unknown filter params fall back to defaults", %{conn: conn} do
    make_card(%{code: "01001a", name: "Spider-Man", type: :hero})

    {:ok, lv, _html} = live(conn, ~p"/cards?aspect=bogus&type=nope")

    html = render_async(lv)

    assert html =~ "Spider-Man"
  end

  test "legacy aspect/type params fold into the query string", %{conn: conn} do
    make_card(%{code: "01001a", name: "Spider-Man", type: :hero})
    make_card(%{code: "01003a", name: "Web Kick", type: :event, ownership: :hero})

    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/cards?type=event&query=web")
    assert to == ~p"/cards?#{[query: "web type:event"]}"

    {:ok, lv, _html} = live(conn, to)
    html = render_async(lv)

    assert html =~ "Web Kick"
    refute html =~ "Spider-Man"
  end

  test "filter sheet changes rewrite the query and narrow results", %{conn: conn} do
    make_card(%{code: "01001a", name: "Spider-Man", type: :hero})
    make_card(%{code: "01003a", name: "Web Kick", type: :event, ownership: :hero})

    {:ok, lv, _html} = live(conn, ~p"/cards")
    render_async(lv)

    lv
    |> form("#card-filters-form")
    |> render_change(%{"type" => ["", "event"]})

    assert_patch(lv, ~p"/cards?#{[query: "type:event"]}")

    html = render_async(lv)

    assert html =~ "Web Kick"
    refute html =~ "Spider-Man"
  end

  test "typed query terms show up as selected sheet controls", %{conn: conn} do
    make_card(%{code: "01003a", name: "Web Kick", type: :event, ownership: :hero})

    {:ok, lv, _html} = live(conn, ~p"/cards?#{[query: "t:event cost<=2 -a:justice"]}")
    render_async(lv)

    assert has_element?(lv, ~s(#card-filters input[value="event"][checked]))

    assert has_element?(
             lv,
             ~s(#card-filters select[name="cost_op"] option[value="lte"][selected])
           )

    assert has_element?(lv, ~s(#card-filters input[name="cost"][value="2"]))

    # the negation isn't form-representable — preserved as residual
    assert lv |> element("#card-filters") |> render() =~ "-a:justice"
  end

  test "the filter button counts active filters", %{conn: conn} do
    make_card(%{code: "01003a", name: "Web Kick", type: :event, ownership: :hero})

    {:ok, lv, _html} = live(conn, ~p"/cards?#{[query: "t:event cost<=2"]}")
    render_async(lv)

    assert lv |> element("button", "Filters") |> render() =~ "2"
  end

  test "restore-scroll reloads through the saved offset and confirms", %{conn: conn} do
    make_card(%{code: "01001a", name: "Spider-Man", type: :hero})
    make_card(%{code: "01002a", name: "Iron Man", type: :hero})

    {:ok, lv, _html} = live(conn, ~p"/cards")
    render_async(lv)

    render_hook(lv, "restore-scroll", %{"offset" => 24})
    html = render_async(lv)

    assert_push_event(lv, "sanctum:scroll-restore", %{})
    assert html =~ "Spider-Man"
    assert html =~ "Iron Man"
  end
end
