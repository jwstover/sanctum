defmodule SanctumWeb.HomebrewLive.EditCardTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.AccountsFixtures
  import Sanctum.Factory

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

  defp edit_path(project, card), do: ~p"/homebrew/#{project.id}/cards/#{card.id}"

  setup %{conn: conn} do
    creator = user_fixture()
    project = project_fixture(creator)
    %{conn: log_in_user(conn, creator), creator: creator, project: project}
  end

  test "anonymous visitors are redirected to sign-in", ctx do
    card = card_fixture(ctx.project, ctx.creator)
    conn = Phoenix.ConnTest.build_conn()

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, edit_path(ctx.project, card))
  end

  test "another user's card is not found", ctx do
    card = card_fixture(ctx.project, ctx.creator)
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(user_fixture())

    assert {:error, {:live_redirect, %{to: "/homebrew"}}} =
             live(conn, edit_path(ctx.project, card))
  end

  test "a card from a different project is not found", ctx do
    other_project = project_fixture(ctx.creator)
    card = card_fixture(other_project, ctx.creator)

    assert {:error, {:live_redirect, %{to: "/homebrew"}}} =
             live(ctx.conn, edit_path(ctx.project, card))
  end

  describe "editing" do
    test "renders prefilled fields with full enum options", ctx do
      card = card_fixture(ctx.project, ctx.creator)
      {:ok, _lv, html} = live(ctx.conn, edit_path(ctx.project, card))

      assert html =~ "edit-card-form-#{card.id}"
      assert html =~ "Test Card"
      assert html =~ "player_side_scheme"
      assert html =~ "https://img.test/a.png"
    end

    test "changes autosave and stay on the page", ctx do
      card = card_fixture(ctx.project, ctx.creator)
      [side] = card.card_sides
      {:ok, lv, _html} = live(ctx.conn, edit_path(ctx.project, card))

      # A (debounced) change event is the save — there is no submit button.
      html =
        lv
        |> form("#edit-card-form-#{card.id}", %{
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
                "scheme" => "2"
              }
            }
          }
        })
        |> render_change()

      updated_side = Ash.get!(Sanctum.Games.CardSide, side.id, authorize?: false)
      assert updated_side.name == "Web Kick"
      assert updated_side.type == :side_scheme
      assert updated_side.cost == 2
      assert updated_side.traits == ["Aerial", "Attack"]
      assert %Sanctum.Games.Stat{value: 3, star: true, consequential: 1} = updated_side.attack
      assert updated_side.scheme == 2

      # Stayed on the page; the art frame follows the new landscape type.
      assert html =~ "All changes saved"
      assert html =~ "aspect-[7/5]"
    end

    test "invalid input does not persist and flags the save state", ctx do
      card = card_fixture(ctx.project, ctx.creator)
      [side] = card.card_sides
      {:ok, lv, _html} = live(ctx.conn, edit_path(ctx.project, card))

      html =
        lv
        |> form("#edit-card-form-#{card.id}", %{
          "card" => %{"card_sides" => %{"0" => %{"id" => side.id, "name" => ""}}}
        })
        |> render_change()

      assert html =~ "Not saved"
      assert Ash.get!(Sanctum.Games.CardSide, side.id, authorize?: false).name == "Test Card"

      # Fixing the field saves again.
      html =
        lv
        |> form("#edit-card-form-#{card.id}", %{
          "card" => %{"card_sides" => %{"0" => %{"id" => side.id, "name" => "Fixed"}}}
        })
        |> render_change()

      assert html =~ "All changes saved"
      assert Ash.get!(Sanctum.Games.CardSide, side.id, authorize?: false).name == "Fixed"
    end

    test "blank optional fields stay blank", ctx do
      card = card_fixture(ctx.project, ctx.creator)
      [side] = card.card_sides
      {:ok, lv, _html} = live(ctx.conn, edit_path(ctx.project, card))

      lv
      |> form("#edit-card-form-#{card.id}", %{
        "card" => %{
          "card_sides" => %{
            "0" => %{
              "id" => side.id,
              "cost" => "",
              "traits_string" => "",
              "attack" => %{"value" => "", "star" => "false", "consequential" => ""}
            }
          }
        }
      })
      |> render_submit()

      updated_side = Ash.get!(Sanctum.Games.CardSide, side.id, authorize?: false)
      assert is_nil(updated_side.cost)
      assert is_nil(updated_side.attack)
      assert updated_side.traits == []
    end

    test "two-sided cards show both fieldsets and can be split", ctx do
      front = card_fixture(ctx.project, ctx.creator, %{filename: "front.png"})
      back = card_fixture(ctx.project, ctx.creator, %{filename: "back.png"})
      {:ok, paired} = Homebrew.pair_custom_cards(front.id, back.id, ctx.creator)

      {:ok, lv, html} = live(ctx.conn, edit_path(ctx.project, paired))

      assert html =~ "Side A"
      assert html =~ "Side B"
      assert html =~ "Split into two cards"
      refute has_element?(lv, "button[phx-click='open_declare_alt']")

      lv |> element("button[phx-click='unpair_card']") |> render_click()

      flash = assert_redirect(lv, ~p"/homebrew/#{ctx.project.id}")
      assert flash["info"] == "Card split into two."
    end
  end

  describe "alt art declaration" do
    defp official_fixture do
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

      {:ok, lv, _html} = live(ctx.conn, edit_path(ctx.project, card))

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

      lv
      |> element("#declare-alt-sheet form[phx-submit='declare_alt']")
      |> render_submit(%{"artist" => "Jane Doe"})

      flash = assert_redirect(lv, ~p"/homebrew/#{ctx.project.id}")
      assert flash["info"] == "Declared as alt art for Official Target."

      alt =
        Sanctum.Games.CardAlt
        |> Ash.Query.filter(origin == :custom and homebrew_project_id == ^ctx.project.id)
        |> Ash.read_one!(authorize?: false)

      assert alt.card_id == official.id
      assert alt.artist == "Jane Doe"
      assert {:error, _} = Ash.get(Sanctum.Games.Card, card.id, authorize?: false)
    end
  end
end
