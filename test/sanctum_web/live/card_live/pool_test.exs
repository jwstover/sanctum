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
end
