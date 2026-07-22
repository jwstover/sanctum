defmodule SanctumWeb.HomebrewLive.ShowTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.AccountsFixtures

  alias Sanctum.Homebrew

  require Ash.Query

  defp project_fixture(actor) do
    Homebrew.create_project!(%{name: "Test Pack", attestation: true}, actor: actor)
  end

  defp card_fixture(project, actor, attrs \\ %{}) do
    {:ok, card} =
      Homebrew.create_custom_card(
        %{
          homebrew_project_id: project.id,
          card_sides: [
            Map.merge(%{image_url: "https://img.test/a.png", filename: "test-card.png"}, attrs)
          ]
        },
        actor
      )

    Ash.load!(card, [:card_sides, :primary_side], authorize?: false)
  end

  # Homebrew is TEMPORARILY admin-gated at the router (see router.ex), so the
  # page tests act as an admin. Cross-user privacy semantics stay covered by
  # the data-layer tests (card_privacy_test etc.), which use plain users.
  setup %{conn: conn} do
    creator = admin_user_fixture()
    project = project_fixture(creator)
    %{conn: log_in_user(conn, creator), creator: creator, project: project}
  end

  test "anonymous visitors are redirected to sign-in", %{project: project} do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/homebrew/#{project.id}")
  end

  test "non-admins are redirected away", %{project: project} do
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(user_fixture())

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/homebrew/#{project.id}")
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/homebrew")
  end

  test "card tiles link to the card's edit page", ctx do
    card = card_fixture(ctx.project, ctx.creator)
    {:ok, _lv, html} = live(ctx.conn, ~p"/homebrew/#{ctx.project.id}")

    assert html =~ ~p"/homebrew/#{ctx.project.id}/cards/#{card.id}"
    assert html =~ "Test Card"
  end

  describe "alt art management" do
    defp official_fixture do
      import Sanctum.Factory

      card = create(Sanctum.Games.Card, attrs: %{code: "91001", base_code: "91001"})

      create(Sanctum.Games.CardSide,
        attrs: %{
          card_id: card.id,
          name: "Official Target",
          code: "91001a",
          side_identifier: "a",
          is_primary_side: true,
          ownership: :player
        }
      )

      card
    end

    test "alts render as target tiles with credit; revert brings the card back", ctx do
      official = official_fixture()
      card = card_fixture(ctx.project, ctx.creator, %{filename: "reverted-fan.png"})

      {:ok, alt} =
        Homebrew.declare_alt_art(card.id, official.id, [artist: "Jane Doe"], ctx.creator)

      {:ok, lv, html} = live(ctx.conn, ~p"/homebrew/#{ctx.project.id}")

      assert html =~ "Alt Art (1)"
      assert html =~ "Official Target"
      assert html =~ "by Jane Doe"
      assert html =~ "1 alt"

      html =
        lv
        |> element("button[phx-click='revert_alt'][phx-value-id='#{alt.id}']")
        |> render_click()

      refute html =~ "Alt Art (1)"
      assert html =~ "Official Target"
    end

    test "delete removes the alt without minting a card", ctx do
      official = official_fixture()
      card = card_fixture(ctx.project, ctx.creator, %{filename: "deleted-fan.png"})
      {:ok, alt} = Homebrew.declare_alt_art(card.id, official.id, [], ctx.creator)

      {:ok, lv, _html} = live(ctx.conn, ~p"/homebrew/#{ctx.project.id}")

      html =
        lv
        |> element("button[phx-click='delete_alt'][phx-value-id='#{alt.id}']")
        |> render_click()

      refute html =~ "Alt Art (1)"
      refute html =~ "Official Target"
    end
  end

  describe "pairing" do
    test "full pair flow: select two, swap, pair", ctx do
      front = card_fixture(ctx.project, ctx.creator, %{filename: "front-face.png"})
      back = card_fixture(ctx.project, ctx.creator, %{filename: "back-face.png"})

      {:ok, lv, html} = live(ctx.conn, ~p"/homebrew/#{ctx.project.id}")
      assert html =~ "Pair fronts &amp; backs"

      lv |> element("button[phx-click='toggle_pair_mode']") |> render_click()

      lv
      |> element("button[phx-click='toggle_pair_select'][phx-value-id='#{front.id}']")
      |> render_click()

      html =
        lv
        |> element("button[phx-click='toggle_pair_select'][phx-value-id='#{back.id}']")
        |> render_click()

      assert html =~ "FRONT"
      assert html =~ "BACK"
      assert html =~ "Front: Front Face"

      html = lv |> element("button[phx-click='swap_pair_order']") |> render_click()
      assert html =~ "Front: Back Face"
      html = lv |> element("button[phx-click='swap_pair_order']") |> render_click()
      assert html =~ "Front: Front Face"

      html = lv |> element("button[phx-click='pair_cards']") |> render_click()

      assert html =~ "Cards paired."
      assert html =~ "1 card"

      paired = Ash.get!(Sanctum.Games.Card, front.id, authorize?: false)
      assert paired.is_multi_sided
      assert {:error, _} = Ash.get(Sanctum.Games.Card, back.id, authorize?: false)
    end

    test "multi-sided cards are not selectable in pair mode", ctx do
      a = card_fixture(ctx.project, ctx.creator)
      b = card_fixture(ctx.project, ctx.creator)
      {:ok, paired} = Homebrew.pair_custom_cards(a.id, b.id, ctx.creator)
      card_fixture(ctx.project, ctx.creator)
      card_fixture(ctx.project, ctx.creator)

      {:ok, lv, _html} = live(ctx.conn, ~p"/homebrew/#{ctx.project.id}")
      html = lv |> element("button[phx-click='toggle_pair_mode']") |> render_click()

      assert html =~ "2-SIDED"

      refute has_element?(
               lv,
               "button[phx-click='toggle_pair_select'][phx-value-id='#{paired.id}']"
             )
    end
  end
end
