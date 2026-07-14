defmodule SanctumWeb.GuessLive.PlayTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.Factory

  # The cards table is empty under `mix test`, so a single seeded flavor card is
  # the only guessable card and gets picked deterministically.
  defp seed_card(name, flavor) do
    card =
      create(Sanctum.Games.Card,
        attrs: %{base_code: "95001", code: "95001", unique: true, deck_limit: 1}
      )

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: card.id,
        code: "95001a",
        side_identifier: "A",
        is_primary_side: true,
        name: name,
        type: :ally,
        ownership: :player,
        aspect: :leadership,
        flavor: flavor,
        traits: ["Avenger"]
      }
    )

    card
  end

  test "shows the flavor text and no answer up front", %{conn: conn} do
    seed_card("Nick Fury", "The ultimate spy.")

    {:ok, _view, html} = live(conn, ~p"/guess")

    assert html =~ "Flavor Town"
    assert html =~ "The ultimate spy."
    refute html =~ "You got it!"
  end

  test "a wrong guess reveals the first hint", %{conn: conn} do
    seed_card("Nick Fury", "The ultimate spy.")

    {:ok, view, _html} = live(conn, ~p"/guess")

    html = view |> form("form", %{guess: "Definitely Wrong"}) |> render_submit()

    assert html =~ "Hints"
    assert html =~ "This is a player card."
    assert html =~ "Missed guesses: Definitely Wrong"
  end

  test "a correct guess wins and reveals the card", %{conn: conn} do
    seed_card("Nick Fury", "The ultimate spy.")

    {:ok, view, _html} = live(conn, ~p"/guess")

    html = view |> form("form", %{guess: "nick fury"}) |> render_submit()

    assert html =~ "You got it!"
    assert html =~ "Nick Fury"
    assert html =~ "Play again"
  end

  test "is reachable by a logged-out visitor", %{conn: conn} do
    seed_card("Nick Fury", "The ultimate spy.")

    assert {:ok, _view, _html} = live(conn, ~p"/guess")
  end
end
