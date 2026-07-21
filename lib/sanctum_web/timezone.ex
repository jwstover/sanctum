defmodule SanctumWeb.Timezone do
  @moduledoc """
  Captures the browser's IANA timezone and shifts stored UTC timestamps into
  it for display.

  The client sends `Intl.DateTimeFormat().resolvedOptions().timeZone` in the
  LiveSocket connect params (see `assets/js/app.js`); the `:assign` on_mount
  hook validates it and assigns `:timezone`. The static (disconnected) render
  has no connect params and falls back to UTC — the connected mount re-renders
  with the local zone.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [get_connect_params: 1]

  @utc "Etc/UTC"

  def on_mount(:assign, _params, _session, socket) do
    timezone =
      case get_connect_params(socket) do
        %{"timezone" => tz} when is_binary(tz) -> validate(tz)
        _ -> @utc
      end

    {:cont, assign(socket, :timezone, timezone)}
  end

  @doc """
  Shifts a UTC `DateTime` into the given zone, returning it unchanged when the
  zone is unknown. Non-DateTime values (nil, `Date`, …) pass through untouched.
  """
  def to_local(%DateTime{} = dt, timezone) do
    case DateTime.shift_zone(dt, timezone) do
      {:ok, shifted} -> shifted
      {:error, _reason} -> dt
    end
  end

  def to_local(other, _timezone), do: other

  defp validate(tz) do
    case DateTime.shift_zone(DateTime.utc_now(), tz) do
      {:ok, _shifted} -> tz
      {:error, _reason} -> @utc
    end
  end
end
