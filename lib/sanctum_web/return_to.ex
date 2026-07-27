defmodule SanctumWeb.ReturnTo do
  @moduledoc """
  Post-sign-in return-path handling.

  Two cooperating pieces:

    * `sign_in_path/1` builds the sign-in URL carrying a `return_to` query param
      — used by LiveViews that bounce a signed-out action (e.g. favoriting a
      deck) to sign-in.
    * the plug (`call/2`) persists that `return_to` into the session on the way
      through the auth routes, so `SanctumWeb.AuthController.success/4` (which
      reads `get_session(conn, :return_to)`) sends the user back where they came
      from once authenticated.

  Both validate that the path is a same-origin absolute path, never a full URL
  or scheme-relative `//host`, so a crafted `return_to` can't become an open
  redirect.
  """

  use SanctumWeb, :verified_routes

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case conn.params["return_to"] do
      path when is_binary(path) ->
        if local_path?(path), do: put_session(conn, :return_to, path), else: conn

      _ ->
        conn
    end
  end

  @doc """
  The sign-in URL, returning the user to `path` afterwards when it's a safe
  local path; otherwise the plain sign-in URL.
  """
  def sign_in_path(path) do
    if is_binary(path) and local_path?(path) do
      ~p"/sign-in?#{[return_to: path]}"
    else
      ~p"/sign-in"
    end
  end

  # Same-origin absolute path only. Rejects "" (not absolute), "//evil.com"
  # (scheme-relative) and "https://evil.com" (absolute URL).
  defp local_path?(path) do
    String.starts_with?(path, "/") and not String.starts_with?(path, "//")
  end
end
