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
        aspect: :justice,
        attack: 2,
        thwart: 3
      }
    )

    {:ok, _view, html} = live(conn, ~p"/cards/#{card}")

    # title + card-level info
    assert html =~ "Test Hero"
    assert html =~ "Card Info"
    assert html =~ "99001"
    # combat stat boxes
    assert html =~ "ATK"
    assert html =~ "THW"
  end
end
