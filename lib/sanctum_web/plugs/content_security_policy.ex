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
        # LiveView applies inline style="" attributes at runtime (aspect colors,
        # resource pips, stat/health badges), which can't be hashed or nonced —
        # so style-src must allow 'unsafe-inline'. Without an explicit style-src,
        # it falls back to default-src 'self' and every inline style is blocked.
        "default-src 'self';" <>
          "style-src 'self' 'unsafe-inline';" <>
          "connect-src wss://#{host} https://#{host}:*#{sentry_ingest_origin()};" <>
          "img-src 'self' blob: data: https: #{img_src_hosts()};" <>
          "font-src 'self' data:;"

      _ ->
        "default-src 'self' 'unsafe-eval' 'unsafe-inline' #{host}:4007;" <>
          "connect-src * ws://#{host}:* http://#{host}:*;" <>
          "img-src 'self' blob: data: https: #{img_src_hosts()};" <>
          "font-src 'self' data:;"
    end
  end

  # The browser SDK posts events directly to Sentry's ingest endpoint, whose
  # host is only knowable from the runtime-provided DSN.
  defp sentry_ingest_origin do
    case Application.get_env(:sentry, :dsn) do
      nil -> ""
      dsn -> " https://#{URI.parse(dsn).host}"
    end
  end

  # NOTE: `img-src` also carries a blanket `https:` (see content_security_policy/0)
  # so deck writeups can render images hotlinked from arbitrary hosts. This is an
  # interim measure — the proper fix (mirror writeup images to our bucket, then
  # drop `https:`) is described in deck-writeup-image-security.md at the repo root.
  #
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
