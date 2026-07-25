defmodule SanctumWeb.ReturnToTest do
  @moduledoc false
  use SanctumWeb.ConnCase, async: true

  alias SanctumWeb.ReturnTo

  describe "sign_in_path/1" do
    test "carries a safe local path as return_to" do
      assert ReturnTo.sign_in_path("/decks") == "/sign-in?return_to=%2Fdecks"

      assert %URI{path: "/sign-in", query: query} =
               URI.parse(ReturnTo.sign_in_path("/decks?query=hero:spider"))

      assert URI.decode_query(query) == %{"return_to" => "/decks?query=hero:spider"}
    end

    test "falls back to plain sign-in for unsafe or missing paths" do
      # Open-redirect vectors and non-paths must not become a return_to.
      for bad <- ["//evil.com", "https://evil.com", "http://evil.com", "", "decks", nil] do
        assert ReturnTo.sign_in_path(bad) == "/sign-in"
      end
    end
  end

  describe "call/2 (plug)" do
    setup do
      {:ok, conn: Plug.Test.init_test_session(build_conn(), %{})}
    end

    test "persists a safe local return_to into the session", %{conn: conn} do
      conn = %{conn | params: %{"return_to" => "/decks?query=hero:spider"}}
      conn = ReturnTo.call(conn, [])

      assert get_session(conn, :return_to) == "/decks?query=hero:spider"
    end

    test "ignores unsafe or absent return_to", %{conn: conn} do
      for bad <- ["//evil.com", "https://evil.com"] do
        result = ReturnTo.call(%{conn | params: %{"return_to" => bad}}, [])
        assert get_session(result, :return_to) == nil
      end

      assert ReturnTo.call(%{conn | params: %{}}, []) |> get_session(:return_to) == nil
    end
  end
end
