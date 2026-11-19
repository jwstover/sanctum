defmodule SanctumWeb.HomebrewLive.SetShowPublishTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.AccountsFixtures

  alias Sanctum.Homebrew
  alias Sanctum.Homebrew.HomebrewSet

  # Homebrew is admin-gated at the router, so the creator is an admin. The
  # publish gates check the set's creator, so that is who these exercise.
  defp setup_set(conn, user_attrs) do
    creator = admin_user_fixture(user_attrs)
    project = Homebrew.create_project!(%{name: "Test Pack", attestation: true}, actor: creator)

    set =
      Homebrew.create_set!(%{homebrew_project_id: project.id, name: "Kingpin"}, actor: creator)

    %{
      conn: log_in_user(conn, creator),
      set: set,
      path: ~p"/homebrew/#{project.id}/sets/#{set.id}"
    }
  end

  defp reload!(set), do: Ash.get!(HomebrewSet, set.id, authorize?: false)

  test "without a username, publishing is replaced by a link to claim one", %{conn: conn} do
    ctx = setup_set(conn, %{})
    {:ok, lv, _html} = live(ctx.conn, ctx.path)

    refute has_element?(lv, "#start-publish")
    assert has_element?(lv, "#publish-needs-username", "claim a username first")
    assert has_element?(lv, ~s(#publish-needs-username a[href="/profile"]))
  end

  test "first publish needs the attestation, then records it", %{conn: conn} do
    ctx = setup_set(conn, %{username: "wilson_fisk"})
    {:ok, lv, _html} = live(ctx.conn, ctx.path)

    refute has_element?(lv, "#publish-needs-username")
    lv |> element("#start-publish") |> render_click()
    assert has_element?(lv, "#publish-attest")

    html = lv |> form("#publish-form", %{attest: "false"}) |> render_submit()
    assert html =~ "Could not change visibility"
    assert reload!(ctx.set).visibility == :private

    # The form stays open for another try.
    html = lv |> form("#publish-form", %{attest: "true"}) |> render_submit()

    assert html =~ "Published Kingpin."
    assert has_element?(lv, ~s(#visibility-rung-published[aria-current="true"]))
    assert has_element?(lv, "#set-public-link")

    published = reload!(ctx.set)
    assert published.visibility == :published
    assert published.attestation
    assert %DateTime{} = published.attested_at
  end

  test "unpublishing returns the set to private and keeps the attestation", %{conn: conn} do
    ctx = setup_set(conn, %{username: "wilson_fisk"})

    Homebrew.set_set_visibility!(ctx.set, :published, %{attest: true},
      actor: nil,
      authorize?: false
    )

    {:ok, lv, _html} = live(ctx.conn, ctx.path)

    html =
      lv
      |> element(~s(#confirm-unpublish button[phx-value-visibility="private"]))
      |> render_click()

    assert html =~ "Set is now private."
    assert has_element?(lv, ~s(#visibility-rung-private[aria-current="true"]))

    reloaded = reload!(ctx.set)
    assert reloaded.visibility == :private
    assert reloaded.attested_at

    # Re-publishing doesn't ask again.
    lv |> element("#start-publish") |> render_click()
    refute has_element?(lv, "#publish-attest")
    lv |> form("#publish-form") |> render_submit()
    assert reload!(ctx.set).visibility == :published
  end

  test "the ladder steps through unlisted", %{conn: conn} do
    ctx = setup_set(conn, %{username: "wilson_fisk"})
    {:ok, lv, _html} = live(ctx.conn, ctx.path)

    lv |> element("#make-unlisted") |> render_click()
    assert reload!(ctx.set).visibility == :unlisted

    lv |> element("#make-private") |> render_click()
    assert reload!(ctx.set).visibility == :private
  end
end
