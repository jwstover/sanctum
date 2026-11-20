defmodule SanctumWeb.HomebrewLive.DirectoryTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.AccountsFixtures
  import Sanctum.HomebrewFixtures

  alias Sanctum.Games
  alias Sanctum.Homebrew

  setup do
    creator = user_fixture(%{username: "matt_murdock"})

    project =
      Homebrew.create_project!(%{name: "Hell's Kitchen", attestation: true}, actor: creator)

    daredevil =
      %{homebrew_project_id: project.id, name: "Daredevil"}
      |> Homebrew.create_set!(actor: creator)
      |> then(&Homebrew.update_set!(&1, %{kind: "Hero", tags: ["noir"]}, actor: creator))
      |> publish_set!(creator)

    Games.create_custom_card!(
      %{
        homebrew_set_id: daredevil.id,
        card_sides: [%{name: "Billy Club", image_url: "https://img.test/club.png"}]
      },
      actor: creator
    )

    loose =
      %{homebrew_project_id: project.id, name: "Loose Scans"}
      |> Homebrew.create_set!(actor: creator)
      |> publish_set!(creator)

    Homebrew.create_set!(%{homebrew_project_id: project.id, name: "Secret"}, actor: creator)

    %{homebrew_project_id: project.id, name: "Elektra"}
    |> Homebrew.create_set!(actor: creator)
    |> then(&Homebrew.set_set_visibility!(&1, :unlisted, actor: creator))

    %{creator: creator, project: project, daredevil: daredevil, loose: loose}
  end

  test "anonymous visitors see only published sets, labelled as fan content", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/custom")

    assert has_element?(lv, "#fan-content-notice", "Unofficial fan content")
    assert has_element?(lv, "#directory-set-#{ctx.daredevil.id} .set-name", "Daredevil")
    assert has_element?(lv, "#directory-set-#{ctx.daredevil.id} .set-creator", "@matt_murdock")
    assert has_element?(lv, "#directory-set-#{ctx.daredevil.id} .set-kind", "Hero")
    assert has_element?(lv, "#directory-set-#{ctx.daredevil.id} .set-card-count", "1 card")
    assert has_element?(lv, "#directory-set-#{ctx.loose.id}")
    refute has_element?(lv, "#directory-sets", "Secret")
    refute has_element?(lv, "#directory-sets", "Elektra")
    assert has_element?(lv, "#directory-count", "2")
  end

  test "the creator doesn't see their own private or unlisted sets listed", ctx do
    {:ok, lv, _html} = live(log_in_user(ctx.conn, ctx.creator), ~p"/custom")

    refute has_element?(lv, "#directory-sets", "Secret")
    refute has_element?(lv, "#directory-sets", "Elektra")
  end

  test "a set with no kind shows as Other and is found under the Other facet", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/custom")
    assert has_element?(lv, "#directory-set-#{ctx.loose.id} .set-kind", "Other")

    {:ok, lv, _html} = live(ctx.conn, ~p"/custom?kind=other")
    assert has_element?(lv, "#directory-set-#{ctx.loose.id}")
    refute has_element?(lv, "#directory-set-#{ctx.daredevil.id}")
  end

  test "facets filter through the URL and combine", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/custom")

    lv |> form("#directory-filters", %{kind: "hero"}) |> render_change()
    assert_patch(lv, ~p"/custom?kind=hero")
    assert has_element?(lv, "#directory-set-#{ctx.daredevil.id}")
    refute has_element?(lv, "#directory-set-#{ctx.loose.id}")

    lv |> form("#directory-filters", %{kind: "hero", tag: "noir"}) |> render_change()
    assert has_element?(lv, "#directory-set-#{ctx.daredevil.id}")

    lv
    |> form("#directory-filters", %{kind: "other", creator: "matt_murdock", tag: "noir"})
    |> render_change()

    assert has_element?(lv, "#directory-empty", "No sets found")

    lv |> element("#clear-filters") |> render_click()
    assert_patch(lv, ~p"/custom")
    assert has_element?(lv, "#directory-set-#{ctx.loose.id}")
  end

  test "facet options list published creators and tags", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/custom")

    assert has_element?(lv, ~s(#filter-creator option[value="matt_murdock"]))
    assert has_element?(lv, ~s(#filter-tag option[value="noir"]))
    assert has_element?(lv, ~s(#filter-kind option[value="other"]))
    assert lv |> element("#filter-kind") |> render() |> String.split("Other") |> length() == 2
  end

  test "an unknown recency value is ignored rather than crashing", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/custom?recency=decade")
    assert has_element?(lv, "#directory-set-#{ctx.daredevil.id}")
  end

  test "a tile opens the set's public page", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/custom")

    {:ok, _set_lv, html} =
      lv
      |> element(~s(#directory-set-#{ctx.daredevil.id} a[href="/custom/@matt_murdock/daredevil"]))
      |> render_click()
      |> follow_redirect(ctx.conn)

    assert html =~ "Billy Club"
  end
end
