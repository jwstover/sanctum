defmodule SanctumWeb.DeployNoticeController do
  @moduledoc """
  CI-facing webhook that announces an imminent deploy to connected users.

  Guarded by a shared bearer token (`DEPLOY_NOTICE_TOKEN` in prod); responds
  404 for missing/invalid tokens and when no token is configured, so the
  route is invisible to probes.
  """

  use SanctumWeb, :controller

  def create(conn, _params) do
    with expected when is_binary(expected) <- configured_token(),
         ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         true <- Plug.Crypto.secure_compare(token, expected) do
      SanctumWeb.DeployNotice.broadcast()
      send_resp(conn, 204, "")
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  defp configured_token, do: Application.get_env(:sanctum, :deploy_notice_token)
end
