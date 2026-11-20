defmodule SanctumWeb.AdminLive.ReportsTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.AccountsFixtures
  import Sanctum.HomebrewFixtures

  alias Sanctum.Homebrew
  alias Sanctum.Homebrew.HomebrewSet

  setup %{conn: conn} do
    creator = user_fixture(%{username: "wilson_fisk"})
    project = Homebrew.create_project!(%{name: "Kingpin", attestation: true}, actor: creator)

    set =
      %{homebrew_project_id: project.id, name: "Kingpin"}
      |> Homebrew.create_set!(actor: creator)
      |> publish_set!(creator)

    report =
      Homebrew.report_set!(
        %{homebrew_set_id: set.id, reason: :copyright, details: "Scanned art"},
        actor: user_fixture(%{username: "karen_page"})
      )

    admin = admin_user_fixture()

    %{conn: log_in_user(conn, admin), admin: admin, creator: creator, set: set, report: report}
  end

  defp reload!(set), do: Ash.get!(HomebrewSet, set.id, authorize?: false)

  test "non-admins are redirected away" do
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(user_fixture())
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/reports")
  end

  test "lists open reports with the set, reason, reporter and details", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/admin/reports")

    row = "#report-#{ctx.report.id}"
    assert has_element?(lv, row, "Kingpin")
    assert has_element?(lv, row, "Copyright or IP infringement")
    assert has_element?(lv, row, "@karen_page")
    assert has_element?(lv, row, "Scanned art")
    assert has_element?(lv, "#{row} a[href='/custom/@wilson_fisk/kingpin']")
  end

  test "taking a set down unpublishes it, keeps it, and clears the report", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/admin/reports")

    lv |> element("#take-down-#{ctx.report.id} [data-confirm-ok]") |> render_click()

    set = reload!(ctx.set)
    assert set.visibility == :private
    assert set.taken_down_at

    refute has_element?(lv, "#report-#{ctx.report.id}")
    assert has_element?(lv, "#reports-empty")
    assert has_element?(lv, "#taken-down-#{set.id}", "Kingpin")

    # The creator still has the set but can't republish it.
    assert {:error, %Ash.Error.Invalid{}} =
             Homebrew.set_set_visibility(set, :published, actor: ctx.creator)

    lv |> element("#restore-#{set.id}") |> render_click()

    assert reload!(ctx.set).taken_down_at == nil
    assert has_element?(lv, "#taken-down-empty")
  end

  test "dismissing a report leaves the set published", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/admin/reports")

    lv |> element("#dismiss-#{ctx.report.id}") |> render_click()

    refute has_element?(lv, "#report-#{ctx.report.id}")
    assert reload!(ctx.set).visibility == :published
  end

  test "the admin landing page links to the queue", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/admin")
    assert has_element?(lv, "a[href='/admin/reports']")
  end
end
