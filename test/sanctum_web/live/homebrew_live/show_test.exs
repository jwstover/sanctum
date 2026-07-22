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

  setup %{conn: conn} do
    creator = user_fixture()
    project = project_fixture(creator)
    %{conn: log_in_user(conn, creator), creator: creator, project: project}
  end

  test "anonymous visitors are redirected to sign-in", %{project: project} do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/homebrew/#{project.id}")
  end

  test "another user's project is not found", %{project: project} do
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(user_fixture())

    assert {:error, {:live_redirect, %{to: "/homebrew"}}} =
             live(conn, ~p"/homebrew/#{project.id}")
  end

  describe "enrichment sheet" do
    test "opens with prefilled fields and full enum options", ctx do
      card = card_fixture(ctx.project, ctx.creator)
      {:ok, lv, _html} = live(ctx.conn, ~p"/homebrew/#{ctx.project.id}")

      html =
        lv
        |> element("button[phx-click='edit_card'][phx-value-id='#{card.id}']")
        |> render_click()

      assert html =~ "enrichment-form-#{card.id}"
      assert html =~ "Test Card"
      assert html =~ "player_side_scheme"
    end

    test "submitting enrichment persists and updates the grid tile", ctx do
      card = card_fixture(ctx.project, ctx.creator)
      [side] = card.card_sides
      {:ok, lv, _html} = live(ctx.conn, ~p"/homebrew/#{ctx.project.id}")

      lv
      |> element("button[phx-click='edit_card'][phx-value-id='#{card.id}']")
      |> render_click()

      html =
        lv
        |> form("#enrichment-form-#{card.id}", %{
          "card" => %{
            "deck_limit" => "1",
            "card_sides" => %{
              "0" => %{
                "id" => side.id,
                "name" => "Web Kick",
                "type" => "side_scheme",
                "cost" => "2",
                "traits_string" => "Aerial, Attack",
                "attack" => %{"value" => "3", "star" => "true", "consequential" => "1"},
                "health" => %{"value" => "4", "star" => "false", "scaling" => "per_player"}
              }
            }
          }
        })
        |> render_submit()

      updated_side = Ash.get!(Sanctum.Games.CardSide, side.id, authorize?: false)
      assert updated_side.name == "Web Kick"
      assert updated_side.type == :side_scheme
      assert updated_side.cost == 2
      assert updated_side.traits == ["Aerial", "Attack"]

      assert %Sanctum.Games.Stat{value: 3, star: true, consequential: 1} = updated_side.attack
      assert %Sanctum.Games.Stat{value: 4, scaling: :per_player} = updated_side.health

      # Scheme types render in the tile's landscape art frame; the sheet
      # closed on save.
      assert html =~ "w-[210px]"
      assert html =~ "Web Kick"
    end

    test "blank optional fields stay blank", ctx do
      card = card_fixture(ctx.project, ctx.creator)
      [side] = card.card_sides
      {:ok, lv, _html} = live(ctx.conn, ~p"/homebrew/#{ctx.project.id}")

      lv
      |> element("button[phx-click='edit_card'][phx-value-id='#{card.id}']")
      |> render_click()

      lv
      |> form("#enrichment-form-#{card.id}", %{
        "card" => %{
          "card_sides" => %{
            "0" => %{
              "id" => side.id,
              "cost" => "",
              "traits_string" => "",
              # An untouched stat row submits all-blank map params — the stat
              # must collapse back to absent, not an empty struct.
              "attack" => %{"value" => "", "star" => "false", "consequential" => ""},
              "health" => %{"value" => "", "star" => "false", "scaling" => "flat"}
            }
          }
        }
      })
      |> render_submit()

      updated_side = Ash.get!(Sanctum.Games.CardSide, side.id, authorize?: false)
      assert is_nil(updated_side.cost)
      assert is_nil(updated_side.attack)
      assert is_nil(updated_side.health)
      assert updated_side.traits == []
    end

    test "two-sided cards show both fieldsets and can be split", ctx do
      front = card_fixture(ctx.project, ctx.creator, %{filename: "front.png"})
      back = card_fixture(ctx.project, ctx.creator, %{filename: "back.png"})
      {:ok, paired} = Homebrew.pair_custom_cards(front.id, back.id, ctx.creator)

      {:ok, lv, _html} = live(ctx.conn, ~p"/homebrew/#{ctx.project.id}")

      html =
        lv
        |> element("button[phx-click='edit_card'][phx-value-id='#{paired.id}']")
        |> render_click()

      assert html =~ "Side A"
      assert html =~ "Side B"
      assert html =~ "Split into two cards"

      lv
      |> element("button[phx-click='unpair_card']")
      |> render_click()

      # Two single-sided tiles again.
      html = render(lv)
      assert html =~ "2 cards"
      refute html =~ "Side B"
    end
  end

  describe "alt art" do
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

    test "declare flow: search, pick, credit, convert", ctx do
      official = official_fixture()
      card = card_fixture(ctx.project, ctx.creator, %{filename: "fan-piece.png"})

      {:ok, lv, _html} = live(ctx.conn, ~p"/homebrew/#{ctx.project.id}")

      lv
      |> element("button[phx-click='edit_card'][phx-value-id='#{card.id}']")
      |> render_click()

      html = lv |> element("button[phx-click='open_declare_alt']") |> render_click()
      assert html =~ "declare-alt-sheet"

      lv
      |> element("#declare-alt-sheet form[phx-change='alt_search']")
      |> render_change(%{"q" => "Official Target"})

      assert has_element?(lv, "#declare-alt-sheet button[phx-click='pick_alt_target']")
      # The picker is pinned to official cards — the custom card is absent
      # even though its name would match the query.
      refute has_element?(
               lv,
               "#declare-alt-sheet button[phx-click='pick_alt_target']",
               "Fan Piece"
             )

      side_id =
        Sanctum.Games.CardSide
        |> Ash.Query.filter(code == "91001a")
        |> Ash.read_one!(authorize?: false)
        |> Map.fetch!(:id)

      html =
        lv
        |> element("button[phx-click='pick_alt_target'][phx-value-id='#{side_id}']")
        |> render_click()

      assert html =~ "Alt art for Official Target"

      html =
        lv
        |> element("#declare-alt-sheet form[phx-submit='declare_alt']")
        |> render_submit(%{"artist" => "Jane Doe"})

      assert html =~ "Declared as alt art for Official Target."
      refute has_element?(lv, "button[phx-click='edit_card'][phx-value-id='#{card.id}']")
      assert html =~ "Alt Art (1)"
      assert html =~ "by Jane Doe"
      assert html =~ "1 alt"

      alt =
        Sanctum.Games.CardAlt
        |> Ash.Query.filter(origin == :custom and homebrew_project_id == ^ctx.project.id)
        |> Ash.read_one!(authorize?: false)

      assert alt.card_id == official.id
      assert {:error, _} = Ash.get(Sanctum.Games.Card, card.id, authorize?: false)
    end

    test "multi-sided cards do not offer the alt-art action", ctx do
      a = card_fixture(ctx.project, ctx.creator)
      b = card_fixture(ctx.project, ctx.creator)
      {:ok, paired} = Homebrew.pair_custom_cards(a.id, b.id, ctx.creator)

      {:ok, lv, _html} = live(ctx.conn, ~p"/homebrew/#{ctx.project.id}")

      html =
        lv
        |> element("button[phx-click='edit_card'][phx-value-id='#{paired.id}']")
        |> render_click()

      assert html =~ "Split into two cards"
      refute has_element?(lv, "button[phx-click='open_declare_alt']")
    end

    test "revert brings the card back; delete does not", ctx do
      official = official_fixture()
      card = card_fixture(ctx.project, ctx.creator, %{filename: "reverted-fan.png"})
      {:ok, alt} = Homebrew.declare_alt_art(card.id, official.id, [], ctx.creator)

      {:ok, lv, _html} = live(ctx.conn, ~p"/homebrew/#{ctx.project.id}")

      html =
        lv
        |> element("button[phx-click='revert_alt'][phx-value-id='#{alt.id}']")
        |> render_click()

      refute html =~ "Alt Art (1)"
      assert html =~ "Official Target"

      # Declare again, then delete outright.
      new_card =
        Sanctum.Games.Card
        |> Ash.Query.filter(origin == :custom and homebrew_project_id == ^ctx.project.id)
        |> Ash.read_one!(authorize?: false)

      {:ok, alt} = Homebrew.declare_alt_art(new_card.id, official.id, [], ctx.creator)
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
