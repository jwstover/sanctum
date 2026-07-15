defmodule SanctumWeb.AdminLive.IndexTest do
  @moduledoc false

  # async: false — the import test toggles the global `:marvel_cdb_req_options`
  # env to route MarvelCDB requests to a Req.Test stub.
  use SanctumWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Sanctum.Factory

  setup %{conn: conn} do
    conn = log_in_user(conn, Sanctum.AccountsFixtures.admin_user_fixture())
    {:ok, conn: conn}
  end

  test "renders the deck import form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin")

    assert html =~ "Import Deck"
    assert html =~ "deck_url"
  end

  test "rejects input that is not a MarvelCDB deck URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin")

    html =
      view
      |> form("form[phx-submit=import_deck]", %{"deck_url" => "https://example.com/nope"})
      |> render_submit()

    assert html =~ "Not a MarvelCDB deck URL"
  end

  test "imports a deck from a pasted URL and links to its deck view", %{conn: conn} do
    seed_catalog()
    stub_decklist_endpoint()

    original = Application.get_env(:sanctum, :marvel_cdb_req_options)

    Application.put_env(:sanctum, :marvel_cdb_req_options,
      plug: {Req.Test, Sanctum.MarvelCdb},
      retry: false
    )

    on_exit(fn -> Application.put_env(:sanctum, :marvel_cdb_req_options, original) end)

    {:ok, view, _html} = live(conn, ~p"/admin")

    # A messy-but-real paste: http scheme + trailing slug, normalized before import.
    view
    |> form("form[phx-submit=import_deck]", %{
      "deck_url" => "http://marvelcdb.com/decklist/view/55555/spider-legend"
    })
    |> render_submit()

    html = render_async(view)

    assert html =~ "Imported"
    assert html =~ "Web Warrior"

    {:ok, deck} = Sanctum.Decks.get_deck_by_mcdb_id("55555")
    assert deck
    assert html =~ ~p"/decks/#{deck.id}"
  end

  # The hero (both sides) and one player card, so the decklist import resolves
  # every code from the local catalog without extra MarvelCDB fetches.
  defp seed_catalog do
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

    player_card = create(Sanctum.Games.Card, attrs: %{base_code: "90051", code: "90051"})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: player_card.id,
        name: "Web Kick",
        type: :event,
        code: "90051",
        side_identifier: "A",
        is_primary_side: true
      }
    )
  end

  defp stub_decklist_endpoint do
    Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
      assert conn.request_path == "/api/public/decklist/55555"

      Req.Test.json(conn, %{
        "id" => 55_555,
        "name" => "Web Warrior",
        "hero_code" => "90050a",
        "meta" => ~s({"aspect":"justice"}),
        "slots" => %{"90051" => 2}
      })
    end)
  end
end
