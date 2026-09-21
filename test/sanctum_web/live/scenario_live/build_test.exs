defmodule SanctumWeb.ScenarioLive.BuildTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.Factory

  alias Sanctum.Games

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

  defp modular_set!(code, name) do
    Sanctum.Catalog.CardSet
    |> Ash.Changeset.for_create(:upsert, %{code: code, name: name, set_type: :modular})
    |> Ash.create!(authorize?: false)
  end

  defp modular_ids(scenario) do
    Games.get_scenario!(scenario.id, load: [:modular_sets], authorize?: false).modular_sets
    |> Enum.map(& &1.id)
  end

  setup do
    villain_set = villain_set!()
    villain_card!(villain_set, "99201", 1, "https://example.test/rhino1.png")
    m1 = modular_set!("zz_mod_one", "Zz Mod One")
    m2 = modular_set!("zz_mod_two", "Zz Mod Two")

    owner = Sanctum.AccountsFixtures.user_fixture(%{username: "zzowner"})

    scenario =
      Games.build_scenario!(%{name: "Zz Mine", villain_set_id: villain_set.id}, actor: owner)

    %{villain_set: villain_set, m1: m1, m2: m2, owner: owner, scenario: scenario}
  end

  test "signed-out visitors are sent to sign in", %{conn: conn, scenario: s} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/scenarios/#{s.id}/build")
  end

  test "a non-owner is sent to the detail page", %{conn: conn, scenario: s} do
    conn = log_in_user(conn, Sanctum.AccountsFixtures.user_fixture())
    to = "/scenarios/#{s.id}"
    assert {:error, {:live_redirect, %{to: ^to}}} = live(conn, ~p"/scenarios/#{s.id}/build")
  end

  test "an official scenario is sent to the detail page", ctx do
    official =
      Games.create_scenario!(%{name: "Zz Official", villain_set_id: ctx.villain_set.id},
        authorize?: false
      )

    conn = log_in_user(ctx.conn, ctx.owner)
    to = "/scenarios/#{official.id}"

    assert {:error, {:live_redirect, %{to: ^to}}} =
             live(conn, ~p"/scenarios/#{official.id}/build")
  end

  test "an unknown id is sent to the browser", ctx do
    conn = log_in_user(ctx.conn, ctx.owner)

    assert {:error, {:live_redirect, %{to: "/scenarios"}}} =
             live(conn, ~p"/scenarios/#{Ecto.UUID.generate()}/build")
  end

  test "toggled modular sets persist across a reload", ctx do
    conn = log_in_user(ctx.conn, ctx.owner)
    {:ok, view, _} = live(conn, ~p"/scenarios/#{ctx.scenario.id}/build")

    view |> element("#modular-set-#{ctx.m1.id}") |> render_click()
    assert modular_ids(ctx.scenario) == [ctx.m1.id]
    assert has_element?(view, "#modular-count", "1 selected")

    {:ok, view, _} = live(conn, ~p"/scenarios/#{ctx.scenario.id}/build")
    assert has_element?(view, ~s(#modular-set-#{ctx.m1.id}[aria-pressed="true"]))
    assert has_element?(view, ~s(#modular-set-#{ctx.m2.id}[aria-pressed="false"]))

    view |> element("#modular-set-#{ctx.m1.id}") |> render_click()
    assert modular_ids(ctx.scenario) == []
  end

  test "renaming autosaves; a blank name is ignored", ctx do
    conn = log_in_user(ctx.conn, ctx.owner)
    {:ok, view, _} = live(conn, ~p"/scenarios/#{ctx.scenario.id}/build")

    html = view |> form("#rename-form", %{name: "Zz Renamed"}) |> render_change()
    assert html =~ "Zz Renamed"
    assert Games.get_scenario!(ctx.scenario.id, authorize?: false).name == "Zz Renamed"

    view |> form("#rename-form", %{name: "   "}) |> render_change()
    assert Games.get_scenario!(ctx.scenario.id, authorize?: false).name == "Zz Renamed"
  end

  test "the description autosaves and shows on re-mount", ctx do
    conn = log_in_user(ctx.conn, ctx.owner)
    {:ok, view, _} = live(conn, ~p"/scenarios/#{ctx.scenario.id}/build")

    view |> form("#description-form", %{description: "Zz notes"}) |> render_change()
    assert Games.get_scenario!(ctx.scenario.id, authorize?: false).description_md == "Zz notes"

    {:ok, view, _} = live(conn, ~p"/scenarios/#{ctx.scenario.id}/build")
    assert has_element?(view, "#scenario-description-input", "Zz notes")
  end

  test "deleting goes through the confirm dialog and returns to the browser", ctx do
    conn = log_in_user(ctx.conn, ctx.owner)
    {:ok, view, _html} = live(conn, ~p"/scenarios/#{ctx.scenario.id}/build")

    assert has_element?(view, "dialog#confirm-delete-scenario")
    refute has_element?(view, "#confirm-delete-scenario [data-confirm]")

    assert {:error, {:live_redirect, %{to: "/scenarios"}}} =
             view
             |> element("#confirm-delete-scenario button[phx-click='delete']")
             |> render_click()

    assert {:error, _} = Games.get_scenario(ctx.scenario.id, authorize?: false)
  end
end
