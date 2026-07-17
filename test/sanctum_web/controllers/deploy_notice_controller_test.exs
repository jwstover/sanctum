defmodule SanctumWeb.DeployNoticeControllerTest do
  use SanctumWeb.ConnCase, async: true

  # Matches config/test.exs
  @token "test-deploy-notice-token"
  @topic "sanctum:deploy_notices"

  test "broadcasts a deploy notice with a valid token", %{conn: conn} do
    Phoenix.PubSub.subscribe(Sanctum.PubSub, @topic)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@token}")
      |> post(~p"/internal/deploy-notice")

    assert response(conn, 204)
    assert_receive {:deploy_notice, message}
    assert message =~ "deploying"
  end

  test "responds 404 and stays silent for an invalid token", %{conn: conn} do
    Phoenix.PubSub.subscribe(Sanctum.PubSub, @topic)

    conn =
      conn
      |> put_req_header("authorization", "Bearer wrong-token")
      |> post(~p"/internal/deploy-notice")

    assert response(conn, 404)
    refute_receive {:deploy_notice, _message}
  end

  test "responds 404 and stays silent without an authorization header", %{conn: conn} do
    Phoenix.PubSub.subscribe(Sanctum.PubSub, @topic)

    conn = post(conn, ~p"/internal/deploy-notice")

    assert response(conn, 404)
    refute_receive {:deploy_notice, _message}
  end
end
