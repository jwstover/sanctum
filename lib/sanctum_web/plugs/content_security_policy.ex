defmodule SanctumWeb.Plugs.ContentSecurityPolicy do
  @behaviour Plug

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    csp_header = content_security_policy()
    put_resp_header(conn, "content-security-policy", csp_header)
  end

  defp get_host do
    :sanctum
    |> Application.get_env(SanctumWeb.Endpoint)
    |> Keyword.fetch!(:url)
    |> Keyword.fetch!(:host)
  end

  defp content_security_policy do
    host = get_host()

    case Mix.env() do
      :prod ->
        "default-src 'self';connect-src wss://#{host};img-src 'self' blob:;"

      _ ->
        "default-src 'self' 'unsafe-eval' 'unsafe-inline' 127.0.0.1:4007;" <>
          "connect-src ws://#{host}:*;" <>
          "img-src 'self' blob: data:;" <>
          "font-src 'self' data:;"
    end
  end
end
