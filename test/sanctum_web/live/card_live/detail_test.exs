defmodule SanctumWeb.CardLive.DetailTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.Factory

  defp make_card do
    card =
      create(Sanctum.Games.Card,
        attrs: %{base_code: "01001", code: "01001a", is_multi_sided: true, pack: "core"}
      )

    hero =
      create(Sanctum.Games.CardSide,
        attrs: %{
          card_id: card.id,
          name: "Spider-Man",
          type: :hero,
          code: "01001a",
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
          code: "01001b",
          side_identifier: "B",
          is_primary_side: false,
          text: "Scientist supreme of Queens."
        }
      )

    {card, hero, alter_ego}
  end

  test "renders every side of a card for anonymous visitors", %{conn: conn} do
    {card, _hero, _alter_ego} = make_card()

    {:ok, _lv, html} = live(conn, ~p"/cards/#{card.id}")

    assert html =~ "Spider-Man"
    assert html =~ "Peter Parker"
    assert html =~ "Spider-sense tingling."
    assert html =~ "Scientist supreme of Queens."
    assert html =~ "01001"
    assert html =~ "2 sides"
  end

  test "shows pack metadata in the card file panel", %{conn: conn} do
    pack =
      Sanctum.Catalog.Pack
      |> Ash.Changeset.for_create(:upsert_from_marvelcdb, %{
        code: "core",
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

    {:ok, _lv, html} = live(conn, ~p"/cards/#{card.id}")

    assert html =~ "Card File"
    assert html =~ "Core Set"
    assert html =~ "Nov 1, 2019"
    assert html =~ ~p"/browse/core"
    assert html =~ "https://marvelcdb.com/card/01001a"
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

    {:ok, _lv, html} = live(conn, ~p"/cards/#{card.id}")

    assert html =~ "Alternate Printings (2)"
    assert html =~ "https://img.example/02001a.png"
    assert html =~ "03001a"
    assert html =~ "no scan"
  end

  test "card pool tiles link to the card detail page", %{conn: conn} do
    {card, _hero, _alter_ego} = make_card()

    {:ok, _lv, html} = live(conn, ~p"/cards")

    assert html =~ ~p"/cards/#{card.id}"
  end
end
