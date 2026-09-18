defmodule SanctumWeb.Plugs.ApiRateLimit do
  @moduledoc """
  Per-IP rate limit for the `:api` pipeline. 30 requests/minute is generous
  for a legitimate importer fetch (one request per deck) while still capping
  scraping. Lives in the pipeline (not a controller) so every future `/api`
  route inherits it.

  Keyed on `fly-client-ip`, which Fly's edge proxy sets/overwrites on every
  request that reaches the app — unlike `x-forwarded-for`, it can't be
  spoofed by the client. Falls back to `conn.remote_ip` for requests that
  bypass Fly's proxy (e.g. tests, local dev).
  """
  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [put_view: 2, render: 2]

  @scale :timer.minutes(1)
  @limit 30

  def init(opts), do: opts

  def call(conn, _opts) do
    case Sanctum.RateLimit.hit({:api, client_ip(conn)}, @scale, @limit) do
      {:allow, _count} ->
        conn

      {:deny, _timeout} ->
        conn
        |> put_status(:too_many_requests)
        |> put_view(json: SanctumWeb.ErrorJSON)
        |> render(:"429")
        |> halt()
    end
  end

  defp client_ip(conn) do
    case get_req_header(conn, "fly-client-ip") do
      [ip | _] -> ip
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
