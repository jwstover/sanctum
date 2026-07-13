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

    case Application.get_env(:sanctum, :env) do
      :prod ->
        "default-src 'self';" <>
          "connect-src wss://#{host} https://#{host}:*;" <>
          "img-src 'self' blob: data: #{img_src_hosts()};" <>
          "font-src 'self' data:;"

      _ ->
        "default-src 'self' 'unsafe-eval' 'unsafe-inline' #{host}:4007;" <>
          "connect-src * ws://#{host}:* http://#{host}:*;" <>
          "img-src 'self' blob: data: #{img_src_hosts()};" <>
          "font-src 'self' data:;"
    end
  end

  # marvelcdb.com stays allowed: ad-hoc deck/card loads and fresh seeds store
  # marvelcdb image URLs until `mix sanctum.sync_cards` rewrites them.
  defp img_src_hosts do
    bucket_host =
      :sanctum
      |> Application.fetch_env!(:card_image_base_url)
      |> URI.parse()
      |> Map.fetch!(:host)

    "https://marvelcdb.com https://#{bucket_host}"
  end
end
