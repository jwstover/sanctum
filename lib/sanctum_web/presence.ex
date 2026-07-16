defmodule SanctumWeb.Presence do
  @moduledoc """
  Tracks connected LiveView sessions for the active-sessions metric.

  Every LiveView in the router's live sessions runs the `:track` on_mount
  hook, which registers the LiveView process under a per-person key —
  the user id when signed in, the socket id otherwise — so one person with
  several tabs counts once. Presence is cluster-aware (nodes cluster via
  DNSCluster on Fly), so counts cover all machines.

  `emit_active_sessions/0` is invoked by a telemetry poller
  (`SanctumWeb.Telemetry`) and emits `[:sanctum, :sessions, :active]`,
  which `Sanctum.Observability` forwards to Sentry as a gauge.
  """

  use Phoenix.Presence, otp_app: :sanctum, pubsub_server: Sanctum.PubSub

  @topic "sanctum:active_sessions"

  def on_mount(:track, _params, _session, socket) do
    if Phoenix.LiveView.connected?(socket) do
      {:ok, _ref} = track(self(), @topic, session_key(socket), %{})
    end

    {:cont, socket}
  end

  @doc "Number of distinct people (presence keys) currently connected."
  def active_sessions_count do
    @topic |> list() |> map_size()
  end

  @doc false
  def emit_active_sessions do
    :telemetry.execute(
      [:sanctum, :sessions, :active],
      %{count: active_sessions_count()},
      %{}
    )
  rescue
    # If Presence isn't running (boot race, crash-restart window), skip the
    # tick — telemetry_poller permanently drops a measurement that raises.
    # A missing tracker surfaces as ArgumentError (ETS lookup on the
    # tracker's table) from list/1.
    ArgumentError -> :ok
  catch
    :exit, _reason -> :ok
  end

  defp session_key(socket) do
    case socket.assigns[:current_user] do
      %{id: id} -> "user:#{id}"
      _anonymous -> "anon:#{socket.id}"
    end
  end
end
