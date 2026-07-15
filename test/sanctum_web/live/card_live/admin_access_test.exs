defmodule SanctumWeb.CardLive.AdminAccessTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @admin_paths ["/admin", "/admin/cards", "/admin/cards/new", "/admin/cards/sync"]

  describe "anonymous visitors" do
    test "are redirected to sign-in", %{conn: conn} do
      for path <- @admin_paths do
        assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, path)
      end
    end
  end

  describe "authenticated non-admins" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, user_fixture())}
    end

    test "are redirected home with a permission error", %{conn: conn} do
      for path <- @admin_paths do
        assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, path)
        assert flash["error"] =~ "permission"
      end
    end
  end

  describe "admins" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, admin_user_fixture())}
    end

    test "can mount the admin pages", %{conn: conn} do
      for path <- @admin_paths do
        assert {:ok, _view, _html} = live(conn, path)
      end
    end
  end
end
