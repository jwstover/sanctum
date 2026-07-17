defmodule SanctumWeb.SearchHelpLiveTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Sanctum.Search.{CardFields, DeckFields}

  test "renders every registered card and deck field", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/search-help")

    for field <- CardFields.fields() ++ DeckFields.fields() do
      assert html =~ field.name
    end
  end

  test "field examples link to live searches", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/search-help")

    assert html =~ "/cards?query="
    assert html =~ "/decks?query="
  end

  test "the card pool links to the help page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/cards")
    assert html =~ "/search-help#cards"
  end

  test "the deck browser links to the help page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/decks")
    assert html =~ "/search-help#decks"
  end
end
