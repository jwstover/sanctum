defmodule SanctumWeb.HomebrewLive.SetShowDetailsTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.AccountsFixtures

  alias Sanctum.Homebrew

  # Homebrew is admin-gated at the router, so these act as an admin (who
  # bypasses policies) — authorization is covered by SetMetadataTest.
  setup %{conn: conn} do
    creator = admin_user_fixture()
    project = Homebrew.create_project!(%{name: "Test Pack", attestation: true}, actor: creator)

    set =
      Homebrew.create_set!(%{homebrew_project_id: project.id, name: "Kingpin"}, actor: creator)

    %{
      conn: log_in_user(conn, creator),
      creator: creator,
      set: set,
      path: ~p"/homebrew/#{project.id}/sets/#{set.id}"
    }
  end

  test "editing details saves metadata and renders it on the set page", ctx do
    {:ok, lv, _html} = live(ctx.conn, ctx.path)

    html = lv |> element("button", "Edit details") |> render_click()
    assert html =~ ~s(id="set-kind-options")
    assert html =~ ~s(<option value="Hero">)

    html =
      lv
      |> form("#set-details-form",
        set: %{
          name: "Kingpin Rising",
          kind: "Villain Pack",
          tags: "street, noir",
          banner_url: "https://img.test/banner.png",
          description: "**Bold** move\n\n<script>alert(1)</script>"
        }
      )
      |> render_submit()

    assert html =~ "Set details saved."
    assert html =~ "Kingpin Rising"
    assert html =~ ~s(src="https://img.test/banner.png")
    assert has_element?(lv, "#set-kind", "Villain Pack")
    assert html =~ "noir"
    assert has_element?(lv, "#set-description strong", "Bold")
    refute html =~ "<script>alert(1)</script>"

    set = Homebrew.get_set!(ctx.set.id, actor: ctx.creator, load: [:set_kind])
    assert set.set_kind.origin == :custom
  end

  test "a blank name shows an error and keeps the editor open", ctx do
    {:ok, lv, _html} = live(ctx.conn, ctx.path)
    lv |> element("button", "Edit details") |> render_click()

    html = lv |> form("#set-details-form", set: %{name: ""}) |> render_submit()

    assert has_element?(lv, "#set-details-form")
    assert html =~ "is required"
    refute html =~ "Set details saved."
  end

  test "non-https banners are not rendered", ctx do
    Homebrew.update_set!(ctx.set, %{banner_url: "javascript:alert(1)"}, actor: ctx.creator)
    {:ok, _lv, html} = live(ctx.conn, ctx.path)
    refute html =~ "javascript:alert(1)\""
  end
end
