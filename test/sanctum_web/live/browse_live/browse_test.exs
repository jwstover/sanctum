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

  describe "collection" do
    import Sanctum.Factory

    setup %{conn: conn} do
      user = Sanctum.AccountsFixtures.user_fixture()
      pack = make_pack("spdr", "SP//dr")

      card = create(Sanctum.Games.Card, attrs: %{pack_id: pack.id, pack: "spdr", set: "spdr"})

      create(Sanctum.Games.CardSide,
        attrs: %{card_id: card.id, name: "Peni Parker", ownership: :player}
      )

      %{conn: log_in_user(conn, user), user: user, pack: pack, card: card}
    end

    test "anonymous visitors see no collection UI", %{pack: pack} do
      {:ok, view, _html} = live(build_conn(), ~p"/browse/#{pack.code}")
      html = render_async(view)

      refute html =~ "Add to Collection"
      refute html =~ "owned"
    end

    test "adding the pack marks every card owned and shows progress", %{
      conn: conn,
      pack: pack,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/browse/#{pack.code}")
      html = render_async(view)

      assert html =~ "Add to Collection"
      assert html =~ "0 / 1 owned"

      html = view |> element(~s{button[phx-click="toggle_pack_owned"]}) |> render_click()

      assert html =~ "In Collection"
      assert html =~ "1 / 1 owned"
      assert Sanctum.Collections.pack_owned?(pack.id, user)

      # The browse index shows the owned chip on the pack tile.
      {:ok, index, _html} = live(conn, ~p"/browse")
      assert render_async(index) =~ "Owned"
    end

    test "a per-card toggle records an override without touching the pack", %{
      conn: conn,
      pack: pack,
      card: card,
      user: user
    } do
      Sanctum.Collections.add_pack!(pack.id, actor: user)

      {:ok, view, _html} = live(conn, ~p"/browse/#{pack.code}")
      render_async(view)

      html =
        view
        |> element(~s{button[phx-click="toggle_card_owned"][phx-value-id="#{card.id}"]})
        |> render_click()

      assert html =~ "0 / 1 owned"
      assert Sanctum.Collections.pack_owned?(pack.id, user)
      refute Ash.get!(Sanctum.Games.Card, card.id, actor: user, load: [:owned]).owned
    end
  end
end
