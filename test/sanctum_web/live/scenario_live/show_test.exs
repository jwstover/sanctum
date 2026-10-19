defmodule SanctumWeb.ScenarioLive.ShowTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.Factory

  defp encounter_card!(set, code, type, side_attrs) do
    card =
      create(Sanctum.Games.Card,
        attrs: %{base_code: code, code: code, set: set.code, card_set_id: set.id, deck_limit: 2}
      )

    create(Sanctum.Games.CardSide,
      attrs:
        Map.merge(
          %{
            card_id: card.id,
            name: "Zz #{type} #{code}",
            type: type,
            code: code,
            side_identifier: "A",
            is_primary_side: true
          },
          side_attrs
        )
    )

    card
  end

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
    assert html =~ ctx.modular.name
    assert html =~ "Official"
    assert html =~ "https://example.test/rhino1.png"
    refute html =~ "https://example.test/rhino2.png"
    refute has_element?(view, "#scenario-build")
  end

  test "the villain cover card shows no card-type label", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/scenarios/#{ctx.mine.id}")
    html = render_async(view)

    assert html =~ "https://example.test/rhino1.png"
    refute html =~ ~r/>\s*EVENT\s*</
  end

  test "the cover shows the scenario name as H1 and the villain name as H2", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/scenarios/#{ctx.mine.id}")
    render_async(view)

    assert has_element?(view, "h1", "Zz Mine")
    assert has_element?(view, "h2#scenario-villain-name", "Zz Rhino 1")
    refute has_element?(view, "#scenario-cover h1")
  end

  test "the cover shows the Villain tag, the pack tag and the stage caption", ctx do
    pack =
      create(Sanctum.Catalog.Pack,
        action: :upsert_from_marvelcdb,
        attrs: %{code: "zz_core", name: "Zz Core Set"}
      )

    Sanctum.Catalog.CardSet
    |> Ash.Changeset.for_create(:upsert, %{
      code: ctx.villain_set.code,
      name: ctx.villain_set.name,
      set_type: :villain,
      pack_id: pack.id
    })
    |> Ash.create!(authorize?: false)

    {:ok, view, _} = live(ctx.conn, ~p"/scenarios/#{ctx.mine.id}")
    render_async(view)

    assert has_element?(view, "#scenario-cover span", ~r/^\s*Villain\s*$/)
    assert has_element?(view, "#scenario-pack-tag", "Zz Core Set")
    assert has_element?(view, "#scenario-villain-stage", "Villain · Stage I")
  end

  test "without a pack the pack tag is hidden; without a stage the caption is just Villain",
       %{conn: conn} do
    bare = villain_set!()

    scenario =
      Sanctum.Games.create_scenario!(%{name: "Zz Bare", villain_set_id: bare.id},
        authorize?: false
      )

    {:ok, view, _} = live(conn, ~p"/scenarios/#{scenario.id}")
    render_async(view)

    refute has_element?(view, "#scenario-pack-tag")
    assert has_element?(view, "#scenario-villain-stage", ~r/^\s*Villain\s*$/)
  end

  test "an official scenario shows the Official badge in the author row", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/scenarios/#{ctx.official.id}")
    render_async(view)

    assert has_element?(view, "#scenario-author", "Official")
    assert has_element?(view, "#scenario-author", "Updated")
  end

  test "signed-out viewers see a user scenario's author", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/scenarios/#{ctx.mine.id}")
    html = render_async(view)

    assert html =~ "@zzbuilder"
    assert has_element?(view, "#scenario-author", "@zzbuilder")
    refute has_element?(view, "#scenario-author", "Official")
    refute has_element?(view, "#scenario-build")
  end

  test "scenario notes render as markdown; without any the panel shows a placeholder", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/scenarios/#{ctx.mine.id}")
    html = render_async(view)
    assert has_element?(view, "#scenario-notes", "Scenario notes")
    assert html =~ "No notes for this scenario."

    Sanctum.Games.set_scenario_description!(ctx.mine, %{description_md: "**Zz bold** notes"},
      actor: ctx.owner
    )

    {:ok, view, _} = live(ctx.conn, ~p"/scenarios/#{ctx.mine.id}")
    html = render_async(view)
    assert has_element?(view, "#scenario-notes")
    assert html =~ "<strong>Zz bold</strong>"
    refute html =~ "No notes for this scenario."
  end

  test "the notes panel has no author byline; the header already credits the author", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/scenarios/#{ctx.mine.id}")
    render_async(view)

    assert has_element?(view, "#scenario-notes", "Scenario notes")
    refute has_element?(view, "#scenario-notes", "@zzbuilder")
  end

  test "the owner gets a Build link", ctx do
    conn = log_in_user(ctx.conn, ctx.owner)
    {:ok, view, _} = live(conn, ~p"/scenarios/#{ctx.mine.id}")
    render_async(view)

    assert has_element?(view, ~s(#scenario-build[href="/scenarios/#{ctx.mine.id}/build"]))
    refute has_element?(view, "#scenario-build[disabled]")
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

  test "a modular set's section shows a card fan; stats are combined in the side panel", ctx do
    encounter_card!(ctx.modular, "88001", :minion, %{
      boost: 2,
      image_url: "https://example.test/88001.png"
    })

    encounter_card!(ctx.modular, "88002", :treachery, %{
      boost: 1,
      image_url: "https://example.test/88002.png"
    })

    encounter_card!(ctx.modular, "88003", :side_scheme, %{
      boost_star: true,
      image_url: "https://example.test/88003.png"
    })

    {:ok, view, _} = live(ctx.conn, ~p"/scenarios/#{ctx.official.id}")
    html = render_async(view)

    assert has_element?(view, "#modular-set-#{ctx.modular.code}")
    # Fan: one card per distinct type, in the modular set's own row. The fan's
    # thumbnails are too small for the name/type overlay, so this only checks
    # via the (unconditional) image alt text, not the rendered title.
    assert html =~ "https://example.test/88001.png"
    assert html =~ "https://example.test/88002.png"
    assert html =~ "https://example.test/88003.png"
    # Content stats are combined (villain set + every modular set) in the
    # page-level side panel, deck-weighted (deck_limit: 2 each here). No
    # boost-curve chart — just the type-count tiles.
    assert has_element?(view, "#scenario-stats")
    assert html =~ "Minions"
    assert html =~ "Treacheries"
    assert html =~ "Side Schemes"
    refute html =~ "Boost curve"
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
