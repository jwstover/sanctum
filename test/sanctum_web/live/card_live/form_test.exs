defmodule SanctumWeb.CardLive.FormTest do
  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Sanctum.Games.{Card, CardSide}

  describe "new card form" do
    setup %{conn: conn} do
      user = Sanctum.AccountsFixtures.admin_user_fixture()
      conn = log_in_user(conn, user)
      {:ok, conn: conn, user: user}
    end

    test "renders new card form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/cards/new")

      assert html =~ "New Card"
      assert html =~ "Card Information"
      assert html =~ "Card Sides"

      # Check for key card-level form fields
      assert html =~ "Base Code"
      assert html =~ "Primary Code"
      assert html =~ "Multi-sided"
    end

    test "validates required fields on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/cards/new")

      # Test card form validation
      html =
        view
        |> element("form")
        |> render_change(%{"card" => %{"base_code" => ""}})

      assert html =~ "is required"
    end

    test "creates card with basic data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/cards/new")

      unique_id = :rand.uniform(100_000)

      {:ok, index_view, _html} =
        view
        |> form("#card-form", %{
          "card" => %{
            "base_code" => "test#{unique_id}",
            "code" => "test#{unique_id}a"
          }
        })
        |> render_submit()
        |> follow_redirect(conn)

      # Verify card was created by checking it appears in the index (loaded async)
      assert render_async(index_view) =~ "test#{unique_id}"
    end

    test "shows validation errors for invalid card data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/cards/new")

      # Submit with missing required fields
      html =
        view
        |> form("#card-form", %{"card" => %{}})
        |> render_submit()

      assert html =~ "is required"
    end

    test "shows card sides section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/cards/new")

      # The card sides section should be visible
      html = view |> render()
      assert html =~ "Card Sides"
      assert html =~ "Multi-sided"
    end
  end

  describe "edit card form" do
    setup %{conn: conn} do
      user = Sanctum.AccountsFixtures.admin_user_fixture()
      conn = log_in_user(conn, user)

      # Create a test card with card side
      unique_id = :rand.uniform(100_000)

      {:ok, card} =
        Card
        |> Ash.Changeset.for_create(:create, %{
          base_code: "edit#{unique_id}",
          code: "edit#{unique_id}a",
          set: "test",
          pack: "test"
        })
        |> Ash.create(authorize?: false)

      {:ok, card_side} =
        CardSide
        |> Ash.Changeset.for_create(:create, %{
          card_id: card.id,
          name: "Existing Card",
          code: "edit#{unique_id}a",
          side_identifier: "A",
          is_primary_side: true,
          type: :ally,
          traits: ["Test", "Trait"]
        })
        |> Ash.create(authorize?: false)

      {:ok, conn: conn, user: user, card: card, card_side: card_side}
    end

    test "renders edit form with existing data", %{conn: conn, card: card} do
      {:ok, _view, html} = live(conn, ~p"/admin/cards/#{card.id}/edit")

      assert html =~ "Edit Card"
      assert html =~ card.base_code
      assert html =~ "Existing Card"
    end

    test "displays traits as comma-separated string", %{conn: conn, card: card} do
      {:ok, _view, html} = live(conn, ~p"/admin/cards/#{card.id}/edit")

      assert html =~ "Test, Trait"
    end

    test "updates existing card basic fields", %{conn: conn, card: card} do
      {:ok, view, _html} = live(conn, ~p"/admin/cards/#{card.id}/edit")

      {:ok, index_view, _html} =
        view
        |> form("#card-form", %{
          "card" => %{"set" => "updated_set"}
        })
        |> render_submit()
        |> follow_redirect(conn)

      assert render_async(index_view) =~ "updated_set"
    end

    test "updates card side fields", %{conn: conn, card: card} do
      {:ok, view, _html} = live(conn, ~p"/admin/cards/#{card.id}/edit")

      {:ok, index_view, _html} =
        view
        |> form("#card-form", %{
          "card" => %{
            "card_sides" => %{
              "0" => %{
                "name" => "Updated Card Side Name",
                "type" => "hero",
                "cost" => "3",
                "attack" => "2",
                "thwart" => "1"
              }
            }
          }
        })
        |> render_submit()
        |> follow_redirect(conn)

      # Verify the card side was updated by checking it appears in the response
      assert render_async(index_view) =~ "Updated Card Side Name"
    end

    test "updates card side traits", %{conn: conn, card: card} do
      {:ok, view, _html} = live(conn, ~p"/admin/cards/#{card.id}/edit")

      {:ok, index_view, _html} =
        view
        |> form("#card-form", %{
          "card" => %{
            "card_sides" => %{
              "0" => %{
                "traits_string" => "Avenger, Spy, Guardian"
              }
            }
          }
        })
        |> render_submit()
        |> follow_redirect(conn)

      # Verify traits were processed correctly
      assert render_async(index_view) =~ "Avenger, Spy, Guardian"
    end

    test "handles validation errors on update", %{conn: conn, card: card} do
      {:ok, view, _html} = live(conn, ~p"/admin/cards/#{card.id}/edit")

      # Try to submit with invalid data
      html =
        view
        |> form("#card-form", %{"card" => %{"base_code" => ""}})
        |> render_submit()

      assert html =~ "is required"
    end
  end

  describe "form navigation" do
    setup %{conn: conn} do
      user = Sanctum.AccountsFixtures.admin_user_fixture()
      conn = log_in_user(conn, user)
      {:ok, conn: conn, user: user}
    end

    test "cancel button navigates back to index", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/cards/new")

      assert {:ok, _, _html} =
               view
               |> element("a", "Cancel")
               |> render_click()
               |> follow_redirect(conn, ~p"/admin/cards")
    end

    test "successful save redirects to index", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/cards/new")

      unique_id = :rand.uniform(100_000)

      {:ok, index_view, _html} =
        view
        |> form("#card-form", %{
          "card" => %{
            "base_code" => "nav#{unique_id}",
            "code" => "nav#{unique_id}a"
          }
        })
        |> render_submit()
        |> follow_redirect(conn)

      assert render_async(index_view) =~ "nav#{unique_id}"
    end
  end
end
