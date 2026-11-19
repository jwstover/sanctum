defmodule SanctumWeb.HomebrewLive.PublicSetTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.AccountsFixtures

  alias Sanctum.Games
  alias Sanctum.Homebrew

  setup do
    creator = user_fixture(%{username: "matt_murdock"})

    project =
      Homebrew.create_project!(%{name: "Hell's Kitchen", attestation: true}, actor: creator)

    set =
      %{homebrew_project_id: project.id, name: "Daredevil", description: "**Fearless**"}
      |> Homebrew.create_set!(actor: creator)
      |> Homebrew.set_set_visibility!(:published, actor: creator)

    Games.create_custom_card!(
      %{
        homebrew_set_id: set.id,
        card_sides: [%{name: "Billy Club", image_url: "https://img.test/club.png"}]
      },
      actor: creator
    )

    %{creator: creator, project: project, set: set}
  end

  test "anyone can open a published set by creator + slug", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/custom/@matt_murdock/daredevil")

    assert html =~ "Daredevil"
    assert has_element?(lv, "#set-creator", "@matt_murdock")
    assert has_element?(lv, "#set-description strong", "Fearless")
    assert has_element?(lv, "#public-set-cards", "Billy Club")
    refute has_element?(lv, "#set-unpublished")
  end

  test "another creator's set with the same slug is a different page", %{conn: conn} do
    other = user_fixture(%{username: "foggy"})
    project = Homebrew.create_project!(%{name: "Nelson", attestation: true}, actor: other)

    %{homebrew_project_id: project.id, name: "Daredevil"}
    |> Homebrew.create_set!(actor: other)
    |> Homebrew.set_set_visibility!(:published, actor: other)

    {:ok, lv, _html} = live(conn, ~p"/custom/@foggy/daredevil")
    assert has_element?(lv, "#set-creator", "@foggy")
    assert has_element?(lv, "#public-set-empty")
  end

  describe "404s" do
    test "unknown username", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, ~p"/custom/@nobody/daredevil") end
    end

    test "unknown slug", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, ~p"/custom/@matt_murdock/elektra") end
    end

    test "old username after a rename", %{conn: conn, creator: creator} do
      creator
      |> Ash.Changeset.for_update(:update_profile, %{username: "the_devil"}, actor: creator)
      |> Ash.update!()

      assert_error_sent 404, fn -> get(conn, ~p"/custom/@matt_murdock/daredevil") end
      assert {:ok, _lv, _html} = live(conn, ~p"/custom/@the_devil/daredevil")
    end

    test "a private set, for anyone but its creator", %{conn: conn} = ctx do
      Homebrew.create_set!(%{homebrew_project_id: ctx.project.id, name: "Elektra"},
        actor: ctx.creator
      )

      assert_error_sent 404, fn -> get(conn, ~p"/custom/@matt_murdock/elektra") end

      stranger = conn |> recycle() |> log_in_user(user_fixture())
      assert_error_sent 404, fn -> get(stranger, ~p"/custom/@matt_murdock/elektra") end

      {:ok, lv, _html} =
        live(log_in_user(build_conn(), ctx.creator), ~p"/custom/@matt_murdock/elektra")

      assert has_element?(lv, "#set-unpublished")
    end
  end

  describe "set workspace link" do
    test "a published set with a claimed handle links to its public page", ctx do
      admin = admin_user_fixture(%{username: "stick"})
      project = Homebrew.create_project!(%{name: "The Chaste", attestation: true}, actor: admin)
      set = Homebrew.create_set!(%{homebrew_project_id: project.id, name: "Stick"}, actor: admin)
      path = ~p"/homebrew/#{project.id}/sets/#{set.id}"
      conn = log_in_user(ctx.conn, admin)

      {:ok, lv, _html} = live(conn, path)
      refute has_element?(lv, "#set-public-link")

      Homebrew.set_set_visibility!(set, :published, actor: admin)
      {:ok, lv, _html} = live(conn, path)
      assert has_element?(lv, ~s(#set-public-link[href="/custom/@stick/stick"]))
    end
  end
end
