defmodule SanctumWeb.ScenarioLive.ShowTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.Factory

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
    villain_set = villain_set!()
    villain_card!(villain_set, "99002", 2, "https://example.test/rhino2.png")
    villain_card!(villain_set, "99001", 1, "https://example.test/rhino1.png")

    modular =
      Sanctum.Catalog.CardSet
      |> Ash.Changeset.for_create(:upsert, %{
        code: "zz_modular",
        name: "Zz Modular",
        set_type: :modular
      })
      |> Ash.create!(authorize?: false)

    owner = Sanctum.AccountsFixtures.user_fixture(%{username: "zzbuilder"})

    official =
      Sanctum.Games.create_scenario!(
        %{name: "Zz Official", villain_set_id: villain_set.id, modular_sets: [modular.id]},
        authorize?: false
      )

    mine =
      Sanctum.Games.build_scenario!(%{name: "Zz Mine", villain_set_id: villain_set.id},
        actor: owner
      )

    %{villain_set: villain_set, modular: modular, owner: owner, official: official, mine: mine}
  end

  test "signed-out viewers see an official scenario", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/scenarios/#{ctx.official.id}")
    html = render_async(view)

    assert html =~ "Zz Official"
    assert html =~ ctx.villain_set.name
    assert html =~ ctx.modular.name
    assert html =~ "Official"
    assert html =~ "https://example.test/rhino1.png"
    refute html =~ "https://example.test/rhino2.png"
    refute has_element?(view, "#scenario-build")
  end

  test "signed-out viewers see a user scenario's author", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/scenarios/#{ctx.mine.id}")
    html = render_async(view)

    assert html =~ "@zzbuilder"
    refute has_element?(view, "#scenario-build")
  end

  test "the owner gets a disabled Build button", ctx do
    conn = log_in_user(ctx.conn, ctx.owner)
    {:ok, view, _} = live(conn, ~p"/scenarios/#{ctx.mine.id}")
    render_async(view)

    assert has_element?(view, "#scenario-build[disabled]")
  end

  test "another signed-in user gets no Build button", ctx do
    conn = log_in_user(ctx.conn, Sanctum.AccountsFixtures.user_fixture())
    {:ok, view, _} = live(conn, ~p"/scenarios/#{ctx.mine.id}")
    render_async(view)

    refute has_element?(view, "#scenario-build")
  end

  test "an unknown id redirects to the scenario browser", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/scenarios/#{Ecto.UUID.generate()}")

    assert_redirect(view, "/scenarios")
  end

  test "a scenario whose set has no villain cards still renders", %{conn: conn} do
    bare = villain_set!()

    scenario =
      Sanctum.Games.create_scenario!(%{name: "Zz Bare", villain_set_id: bare.id},
        authorize?: false
      )

    {:ok, view, _} = live(conn, ~p"/scenarios/#{scenario.id}")
    html = render_async(view)

    assert html =~ "Zz Bare"
    assert html =~ "No modular sets."
  end
end
