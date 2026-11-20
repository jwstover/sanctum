defmodule SanctumWeb.HomebrewLive.PublicSetTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Sanctum.HomebrewFixtures

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
      |> publish_set!(creator)

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
    |> publish_set!(other)

    {:ok, lv, _html} = live(conn, ~p"/custom/@foggy/daredevil")
    assert has_element?(lv, "#set-creator", "@foggy")
    assert has_element?(lv, "#public-set-empty")
  end

  test "the page carries the fan-content label and a report button", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/custom/@matt_murdock/daredevil")

    assert has_element?(lv, "#fan-content-notice", "Unofficial fan content")
    assert has_element?(lv, "#report-set")
  end

  test "contents are grouped by published child set", %{conn: conn} = ctx do
    nemesis =
      %{homebrew_project_id: ctx.project.id, name: "Bullseye"}
      |> Homebrew.create_set!(actor: ctx.creator)
      |> then(&Homebrew.set_set_parent!(&1, ctx.set.id, actor: ctx.creator))
      |> then(&Homebrew.update_set!(&1, %{kind: "Modular"}, actor: ctx.creator))
      |> publish_set!(ctx.creator)

    Games.create_custom_card!(
      %{
        homebrew_set_id: nemesis.id,
        card_sides: [%{name: "Playing Card", image_url: "https://img.test/card.png"}]
      },
      actor: ctx.creator
    )

    draft =
      %{homebrew_project_id: ctx.project.id, name: "Draft Ideas"}
      |> Homebrew.create_set!(actor: ctx.creator)
      |> then(&Homebrew.set_set_parent!(&1, ctx.set.id, actor: ctx.creator))

    {:ok, lv, _html} = live(conn, ~p"/custom/@matt_murdock/daredevil")

    assert has_element?(lv, "#public-set-cards", "Billy Club")
    refute has_element?(lv, "#public-set-cards", "Playing Card")
    assert has_element?(lv, "#child-set-#{nemesis.id}", "Bullseye")
    assert has_element?(lv, "#child-set-#{nemesis.id}", "Modular")
    assert has_element?(lv, "#child-set-#{nemesis.id}", "Playing Card")
    refute has_element?(lv, "#child-set-#{draft.id}")
    refute render(lv) =~ "Draft Ideas"

    # The creator's public page shows the public view too.
    {:ok, lv, _html} =
      live(log_in_user(build_conn(), ctx.creator), ~p"/custom/@matt_murdock/daredevil")

    refute has_element?(lv, "#child-set-#{draft.id}")
  end

  test "a set of 200 loose, unenriched images still renders and is shareable",
       %{conn: conn} = ctx do
    set =
      %{homebrew_project_id: ctx.project.id, name: "!!!"}
      |> Homebrew.create_set!(actor: ctx.creator)
      |> publish_set!(ctx.creator)

    assert set.slug == "set"

    for n <- 1..200 do
      Games.create_custom_card!(
        %{homebrew_set_id: set.id, card_sides: [%{image_url: "https://img.test/#{n}.png"}]},
        actor: ctx.creator
      )
    end

    {:ok, dir, _html} = live(conn, ~p"/custom")
    assert has_element?(dir, "#directory-set-#{set.id} .set-card-count", "200 cards")

    {:ok, lv, html} =
      dir
      |> element(~s(#directory-set-#{set.id} a[href="/custom/@matt_murdock/set"]))
      |> render_click()
      |> follow_redirect(conn)

    assert has_element?(lv, "#public-set-cards", "200 cards")
    assert html |> String.split("https://img.test/") |> length() == 201
  end

  describe "unlisted sets" do
    setup ctx do
      set =
        %{homebrew_project_id: ctx.project.id, name: "Elektra"}
        |> Homebrew.create_set!(actor: ctx.creator)
        |> then(&Homebrew.set_set_visibility!(&1, :unlisted, actor: ctx.creator))

      Games.create_custom_card!(
        %{
          homebrew_set_id: set.id,
          card_sides: [%{name: "Sai", image_url: "https://img.test/sai.png"}]
        },
        actor: ctx.creator
      )

      %{unlisted: set}
    end

    test "an anonymous visitor opens one, cards included, by its link", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/custom/@matt_murdock/elektra")

      assert has_element?(lv, "#set-unlisted")
      refute has_element?(lv, "#set-unpublished")
      assert has_element?(lv, "#public-set-cards", "Sai")
    end

    test "another signed-in user opens one by its link", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      {:ok, lv, _html} = live(conn, ~p"/custom/@matt_murdock/elektra")
      assert has_element?(lv, "#public-set-cards", "Sai")
    end

    test "back to private, the link 404s again", %{conn: conn} = ctx do
      Homebrew.set_set_visibility!(ctx.unlisted, :private, actor: ctx.creator)
      assert_error_sent 404, fn -> get(conn, ~p"/custom/@matt_murdock/elektra") end
    end
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

      publish_set!(set, admin)
      {:ok, lv, _html} = live(conn, path)
      assert has_element?(lv, ~s(#set-public-link[href="/custom/@stick/stick"]))
    end
  end
end
