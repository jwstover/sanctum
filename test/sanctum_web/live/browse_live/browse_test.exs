defmodule SanctumWeb.BrowseLiveTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defp make_pack(code, name) do
    Sanctum.Catalog.Pack
    |> Ash.Changeset.for_create(:upsert_from_marvelcdb, %{code: code, name: name})
    |> Ash.create!(authorize?: false)
    |> Ash.Changeset.for_update(:set_curated, %{product_type: :hero_pack})
    |> Ash.update!(authorize?: false)
  end

  test "the browser paints its shell, then loads products asynchronously", %{conn: conn} do
    make_pack("spdr", "SP//dr")

    {:ok, view, html} = live(conn, ~p"/browse")

    # Header is on the shell; the product taxonomy loads asynchronously.
    assert html =~ "Browse"

    html = render_async(view)
    assert html =~ "SP//dr"
  end

  test "a product page paints its shell, then loads the pack asynchronously", %{conn: conn} do
    make_pack("spdr", "SP//dr")

    {:ok, view, _html} = live(conn, ~p"/browse/spdr")

    html = render_async(view)
    assert html =~ "SP//dr"
    # No cards synced for this pack yet, so the empty-state panel shows.
    assert html =~ "No cards have been synced"
  end

  test "an unknown product code redirects back to the browser", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/browse/nope")

    # The async load resolves to not-found and redirects to /browse.
    assert_redirect(view, ~p"/browse")
  end

  test "the browser confirms restore-scroll once the taxonomy has loaded", %{conn: conn} do
    make_pack("spdr", "SP//dr")

    {:ok, view, _html} = live(conn, ~p"/browse")

    render_hook(view, "restore-scroll", %{"offset" => 0})
    render_async(view)

    assert_push_event(view, "sanctum:scroll-restore", %{})
  end

  test "a product page confirms restore-scroll once the pack has loaded", %{conn: conn} do
    make_pack("spdr", "SP//dr")

    {:ok, view, _html} = live(conn, ~p"/browse/spdr")

    render_hook(view, "restore-scroll", %{"offset" => 0})
    render_async(view)

    assert_push_event(view, "sanctum:scroll-restore", %{})
  end
end
