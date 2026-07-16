defmodule SanctumWeb.CardLive.ShowTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.Factory

  setup %{conn: conn} do
    %{conn: log_in_user(conn, Sanctum.AccountsFixtures.admin_user_fixture())}
  end

  test "renders the card detail with its sides", %{conn: conn} do
    card = create(Sanctum.Games.Card, attrs: %{base_code: "99001", code: "99001"})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: card.id,
        name: "Test Hero",
        code: "99001a",
        side_identifier: "A",
        is_primary_side: true,
        type: :hero,
        ownership: :player,
        aspect: :justice,
        attack: %{value: 2},
        thwart: %{value: 3}
      }
    )

    {:ok, _view, html} = live(conn, ~p"/admin/cards/#{card}")

    # title + card-level info
    assert html =~ "Test Hero"
    assert html =~ "Card Info"
    assert html =~ "99001"
    # combat stat boxes
    assert html =~ "ATK"
    assert html =~ "THW"
  end

  describe "image replacement" do
    setup do
      card = create(Sanctum.Games.Card, attrs: %{base_code: "99002", code: "99002"})

      side =
        create(Sanctum.Games.CardSide,
          attrs: %{
            card_id: card.id,
            name: "Giant Test",
            code: "99002c",
            side_identifier: "C",
            is_primary_side: true,
            type: :hero,
            ownership: :player,
            image_url: "https://sanctum-cards.fly.storage.tigris.dev/cards/99002c.png"
          }
        )

      %{card: card, side: side}
    end

    test "each side offers a replace-image control", %{conn: conn, card: card} do
      {:ok, _view, html} = live(conn, ~p"/admin/cards/#{card}")
      assert html =~ "Replace image"
    end

    test "starting a replace reveals the upload form; cancel collapses it", %{
      conn: conn,
      card: card,
      side: side
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/cards/#{card}")

      html = render_click(view, "start_replace", %{"side" => side.id})
      assert html =~ "upload-#{side.id}"
      assert html =~ "Save"
      assert html =~ "Cancel"

      html = render_click(view, "cancel_replace", %{})
      refute html =~ "upload-#{side.id}"
      assert html =~ "Replace image"
    end
  end
end
