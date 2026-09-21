defmodule SanctumWeb.ScenarioLive.NewTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.Factory

  require Ash.Query

  defp villain_card!(set, code, stage, image_url) do
    card = create(Sanctum.Games.Card, attrs: %{base_code: code, code: code, set: set.code})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: card.id,
        name: "Zz Rhino #{stage}",
        type: :villain,
        stage: stage,
        code: code,
        side_identifier: "A",
        is_primary_side: true,
        image_url: image_url
      }
    )

    card
  end

  setup do
    set_a = villain_set!("zz_alpha")
    set_b = villain_set!("zz_bravo")
    villain_card!(set_a, "99101", 1, "https://example.test/alpha1.png")

    Sanctum.Catalog.CardSet
    |> Ash.Changeset.for_create(:upsert, %{
      code: "zz_modular",
      name: "Zz Modular",
      set_type: :modular
    })
    |> Ash.create!(authorize?: false)

    user = Sanctum.AccountsFixtures.user_fixture(%{username: "zzpicker"})
    %{set_a: set_a, set_b: set_b, user: user}
  end

  test "signed-out visitors are sent to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/scenarios/new")
  end

  test "lists villain sets with art but not modular sets", ctx do
    {:ok, _view, html} = live(log_in_user(ctx.conn, ctx.user), ~p"/scenarios/new")

    assert html =~ "Villain zz_alpha"
    assert html =~ "Villain zz_bravo"
    assert html =~ "https://example.test/alpha1.png"
    refute html =~ "Zz Modular"
  end

  test "the filter narrows the list", ctx do
    {:ok, view, _html} = live(log_in_user(ctx.conn, ctx.user), ~p"/scenarios/new")

    view |> form("#villain-filter", %{q: "zz_alpha"}) |> render_change()

    assert has_element?(view, "#villain-set-#{ctx.set_a.id}")
    refute has_element?(view, "#villain-set-#{ctx.set_b.id}")
  end

  test "picking a set builds a scenario and opens the builder", ctx do
    {:ok, view, _html} = live(log_in_user(ctx.conn, ctx.user), ~p"/scenarios/new")

    assert {:error, {:live_redirect, %{to: to}}} =
             view |> element("#villain-set-#{ctx.set_a.id}") |> render_click()

    [scenario] =
      Sanctum.Games.Scenario
      |> Ash.Query.filter(owner_id == ^ctx.user.id)
      |> Ash.read!(authorize?: false)

    assert scenario.villain_set_id == ctx.set_a.id
    assert scenario.name == "#{ctx.set_a.name} Scenario"
    assert to == "/scenarios/#{scenario.id}/build"
  end
end
