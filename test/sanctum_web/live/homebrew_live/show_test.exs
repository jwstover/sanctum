defmodule SanctumWeb.HomebrewLive.ShowTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.AccountsFixtures

  alias Sanctum.Homebrew

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

      # Scheme types render landscape; the sheet closed on save.
      assert html =~ "aspect-[88/63]"
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
