defmodule SanctumWeb.HomeLive.IndexTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.Factory

  test "renders the landing page shell for anonymous visitors", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Card of the Day"
    assert html =~ "Latest Decks"
  end

  test "shows empty states once the load lands on an empty vault", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    html = render_async(view)

    assert html =~ "No cards in the vault yet"
    assert html =~ "No decks in the vault yet"
  end

  test "shows the daily card once loaded", %{conn: conn} do
    # Outside the "01001"/"core" namespace the async sync tests upsert.
    card = create(Sanctum.Games.Card, attrs: %{base_code: "61001", code: "61001"})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: card.id,
        name: "Daily Test Card",
        code: "61001",
        type: :ally,
        image_url: "https://example.com/daily.png"
      }
    )

    {:ok, view, _html} = live(conn, ~p"/")

    assert render_async(view) =~ "Daily Test Card"
  end
end
