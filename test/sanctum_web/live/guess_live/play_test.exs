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

    # The round's random card is picked asynchronously after mount.
    {:ok, view, html} = live(conn, ~p"/flavor-town")
    assert html =~ "Flavor Town"

    html = render_async(view)
    assert html =~ "The ultimate spy."
    refute html =~ "You got it!"
  end

  test "a wrong guess reveals the first hint", %{conn: conn} do
    seed_card("Nick Fury", "The ultimate spy.")

    {:ok, view, _html} = live(conn, ~p"/flavor-town")
    render_async(view)

    html =
      view |> form(~s(form[phx-submit="guess"]), %{guess: "Definitely Wrong"}) |> render_submit()

    assert html =~ "Hints"
    assert html =~ "It comes from the “Core” pack."
    assert html =~ "Missed guesses: Definitely Wrong"
  end

  test "a correct guess wins and reveals the card", %{conn: conn} do
    seed_card("Nick Fury", "The ultimate spy.")

    {:ok, view, _html} = live(conn, ~p"/flavor-town")
    render_async(view)

    html = view |> form(~s(form[phx-submit="guess"]), %{guess: "nick fury"}) |> render_submit()

    assert html =~ "You got it!"
    assert html =~ "Nick Fury"
    assert html =~ "Play again"
  end

  test "is reachable by a logged-out visitor", %{conn: conn} do
    seed_card("Nick Fury", "The ultimate spy.")

    assert {:ok, _view, _html} = live(conn, ~p"/flavor-town")
  end

  test "the reveal frames landscape types (side schemes) in landscape", %{conn: conn} do
    card = create(Sanctum.Games.Card, attrs: %{base_code: "95002", code: "95002"})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: card.id,
        code: "95002a",
        name: "Alpha Flight Station",
        type: :side_scheme,
        ownership: :encounter,
        aspect: nil,
        cost: nil,
        flavor: "Keep your sensors locked."
      }
    )

    {:ok, view, _html} = live(conn, ~p"/flavor-town")
    render_async(view)

    html = view |> element(~s(button[phx-click="give-up"])) |> render_click()

    assert html =~ "h-[200px] w-[280px]"
    refute html =~ "h-[280px] w-[200px]"
  end
end
