defmodule SanctumWeb.CardLive.DetailTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.Factory

  # Deliberately outside the "01001"/"core" namespace the async sync tests
  # upsert — colliding unique keys across sandboxed transactions deadlock.
  defp make_card do
    card =
      create(Sanctum.Games.Card,
        attrs: %{base_code: "60001", code: "60001a", is_multi_sided: true, pack: "core"}
      )

    hero =
      create(Sanctum.Games.CardSide,
        attrs: %{
          card_id: card.id,
          name: "Spider-Man",
          type: :hero,
          code: "60001a",
          side_identifier: "A",
          is_primary_side: true,
          text: "Spider-sense tingling."
        }
      )

    alter_ego =
      create(Sanctum.Games.CardSide,
        attrs: %{
          card_id: card.id,
          name: "Peter Parker",
          type: :alter_ego,
          code: "60001b",
          side_identifier: "B",
          is_primary_side: false,
          text: "Scientist supreme of Queens."
        }
      )

    {card, hero, alter_ego}
  end

  test "renders every side of a card for anonymous visitors", %{conn: conn} do
    {card, _hero, _alter_ego} = make_card()

    # The card detail loads asynchronously after mount; await it.
    {:ok, lv, _html} = live(conn, ~p"/cards/#{card.id}")
    html = render_async(lv)

    assert html =~ "Spider-Man"
    assert html =~ "Peter Parker"
    assert html =~ "Spider-sense tingling."
    assert html =~ "Scientist supreme of Queens."
    assert html =~ "60001"
  end

  test "shows pack metadata in the card file panel", %{conn: conn} do
    pack =
      Sanctum.Catalog.Pack
      |> Ash.Changeset.for_create(:upsert_from_marvelcdb, %{
        code: "det_core",
        name: "Core Set",
        released_on: ~D[2019-11-01]
      })
      |> Ash.create!(authorize?: false)
      |> Ash.Changeset.for_update(:set_curated, %{product_type: :core})
      |> Ash.update!(authorize?: false)

    {card, _hero, _alter_ego} = make_card()

    card
    |> Ash.Changeset.for_update(:update, %{pack_id: pack.id})
    |> Ash.update!(authorize?: false)

    {:ok, lv, _html} = live(conn, ~p"/cards/#{card.id}")
    html = render_async(lv)

    assert html =~ "Card File"
    assert html =~ "Core Set"
    assert html =~ "Nov 1, 2019"
    assert html =~ ~p"/browse/det_core"
    assert html =~ "https://marvelcdb.com/card/60001a"
  end

  test "shows every alternate printing, with a placeholder when there is no scan", %{conn: conn} do
    {card, _hero, _alter_ego} = make_card()

    for {code, image_url} <- [{"02001a", "https://img.example/02001a.png"}, {"03001a", nil}] do
      Sanctum.Games.CardAlt
      |> Ash.Changeset.for_create(:create, %{
        card_id: card.id,
        code: code,
        base_code: String.slice(code, 0..4),
        side_identifier: "A",
        pack: "reprint",
        image_url: image_url
      })
      |> Ash.create!(authorize?: false)
    end

    {:ok, lv, _html} = live(conn, ~p"/cards/#{card.id}")
    html = render_async(lv)

    assert html =~ "Alternate Printings (2)"
    assert html =~ "https://img.example/02001a.png"
    assert html =~ "03001a"
    assert html =~ "no scan"
  end

  describe "custom alt art in the printings strip" do
    setup %{conn: conn} do
      {card, _hero, _alter_ego} = make_card()

      creator = Sanctum.AccountsFixtures.user_fixture()

      project =
        Sanctum.Homebrew.create_project!(%{name: "Fan Pack", attestation: true}, actor: creator)

      {:ok, source} =
        Sanctum.Homebrew.create_custom_card(
          %{
            homebrew_project_id: project.id,
            card_sides: [%{image_url: "https://img.test/fan.png", filename: "fan.png"}]
          },
          creator
        )

      {:ok, alt} =
        Sanctum.Homebrew.declare_alt_art(source.id, card.id, [artist: "Jane Doe"], creator)

      %{conn: conn, card: card, creator: creator, project: project, alt: alt}
    end

    test "creator sees the fan art with credit, never the synthetic code", ctx do
      conn = log_in_user(ctx.conn, ctx.creator)
      {:ok, lv, _html} = live(conn, ~p"/cards/#{ctx.card.id}")
      html = render_async(lv)

      assert html =~ "fan art · by Jane Doe"
      assert html =~ "https://img.test/fan.png"
      refute html =~ "custom-"
      # Fan art is not a printing.
      assert html =~ "Alternate Printings (1)"
    end

    test "private fan art is hidden from other users and anonymous visitors", ctx do
      other_conn =
        log_in_user(Phoenix.ConnTest.build_conn(), Sanctum.AccountsFixtures.user_fixture())

      for conn <- [other_conn, ctx.conn] do
        {:ok, lv, _html} = live(conn, ~p"/cards/#{ctx.card.id}")
        html = render_async(lv)

        refute html =~ "fan art"
        refute html =~ "https://img.test/fan.png"
      end
    end

    test "published fan art is visible to everyone", ctx do
      Sanctum.Homebrew.set_project_visibility!(ctx.project, :published, actor: ctx.creator)

      {:ok, lv, _html} = live(ctx.conn, ~p"/cards/#{ctx.card.id}")
      html = render_async(lv)

      assert html =~ "fan art · by Jane Doe"
    end
  end

  test "card pool tiles link to the card detail page", %{conn: conn} do
    {card, _hero, _alter_ego} = make_card()

    # The pool loads its cards asynchronously after mount, so wait for the
    # async read to settle before asserting the tile is present.
    {:ok, lv, _html} = live(conn, ~p"/cards")

    assert render_async(lv) =~ ~p"/cards/#{card.id}"
  end

  describe "collection" do
    setup %{conn: conn} do
      user = Sanctum.AccountsFixtures.user_fixture()

      pack =
        create(Sanctum.Catalog.Pack,
          action: :upsert_from_marvelcdb,
          attrs: %{code: "det_core", name: "Core Set"}
        )

      {card, _hero, _alter_ego} = make_card()

      card
      |> Ash.Changeset.for_update(:update, %{pack_id: pack.id})
      |> Ash.update!(authorize?: false)

      %{conn: log_in_user(conn, user), user: user, pack: pack, card: card}
    end

    test "anonymous visitors see no collection UI", %{card: card} do
      {:ok, lv, _html} = live(build_conn(), ~p"/cards/#{card.id}")
      html = render_async(lv)

      refute html =~ "Collection</div>"
      refute html =~ "Add to Collection"
    end

    test "toggling the card records an owned override", %{conn: conn, card: card, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/cards/#{card.id}")
      render_async(lv)

      html = lv |> element("button", "Add to Collection") |> render_click()

      assert html =~ "In Collection"
      assert Ash.get!(Sanctum.Games.Card, card.id, actor: user, load: [:owned]).owned
    end

    test "toggling the pack flips the card's derived ownership", %{
      conn: conn,
      card: card,
      user: user,
      pack: pack
    } do
      {:ok, lv, _html} = live(conn, ~p"/cards/#{card.id}")
      render_async(lv)

      html =
        lv
        |> element(~s{button[phx-click="toggle_pack_owned"]})
        |> render_click()

      assert html =~ "In Collection"
      assert html =~ "in collection — remove"
      assert Sanctum.Collections.pack_owned?(pack.id, user)
      assert Ash.get!(Sanctum.Games.Card, card.id, actor: user, load: [:owned]).owned
    end

    test "card pool shows the owned chip only to the owner", %{
      conn: conn,
      user: user,
      pack: pack,
      card: card
    } do
      Sanctum.Collections.add_pack!(pack.id, actor: user)

      {:ok, lv, _html} = live(conn, ~p"/cards")
      assert render_async(lv) =~ "In your collection"

      {:ok, anon_lv, _html} = live(build_conn(), ~p"/cards")
      anon_html = render_async(anon_lv)
      assert anon_html =~ ~p"/cards/#{card.id}"
      refute anon_html =~ "In your collection"
    end
  end
end
