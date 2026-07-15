defmodule SanctumWeb.ObanDashboardAccessTest do
  @moduledoc """
  The Oban dashboard builds its own live_session outside our
  `:admin_routes` live session, so it's gated by the `:require_admin`
  conn plug rather than the `:live_admin_required` on_mount hook. These
  tests pin that plug's behavior.
  """

  use SanctumWeb.ConnCase, async: true

  describe "GET /admin/oban" do
    test "redirects anonymous visitors home", %{conn: conn} do
      conn = get(conn, "/admin/oban")
      assert redirected_to(conn) == "/"
    end

    test "redirects authenticated non-admins home", %{conn: conn} do
      conn =
        conn
        |> log_in_user(user_fixture())
        |> get("/admin/oban")

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "permission"
    end
  end
end
