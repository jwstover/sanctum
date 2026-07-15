defmodule Sanctum.AutoShutdown do
  @moduledoc """
  Gracefully stops the node once it is idle — no active HTTP/WebSocket
  connections and no runnable Oban jobs — so Fly.io can scale the machine to
  zero.

  Fly's proxy-based autostop is blind to background work: it decides purely from
  inbound HTTP connections, so it would happily stop a machine mid-Oban-job,
  leaving the job orphaned. Instead we turn Fly autostop *off*
  (`auto_stop_machines = "off"` in fly.toml, with `auto_start_machines = true`)
  and let the node decide when it is safe to stop — because only the node knows
  whether Oban is busy. `auto_start_machines` still boots the machine on the next
  request, preserving scale-to-zero.

  Runs only when the `:auto_stop` application env is true (set in prod via
  runtime.exs). Elsewhere `init/1` returns `:ignore`, so it is a no-op in dev and
  test and never self-terminates the node.
  """
  use GenServer

  require Logger

  # States that mean "there is work due right now". Jobs that are merely
  # `scheduled`/`retryable` for the future are intentionally excluded: the node
  # may sleep and Oban promotes them to `available` on the next boot.
  @busy_states ["available", "executing"]

  @default_interval :timer.minutes(10)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    if Keyword.get(opts, :enabled?, false) do
      interval = Keyword.get(opts, :interval, @default_interval)
      {:ok, %{interval: interval}, {:continue, :schedule}}
    else
      :ignore
    end
  end

  @impl true
  def handle_continue(:schedule, state) do
    schedule_check(state.interval)
    {:noreply, state}
  end

  @impl true
  def handle_info(:check, state) do
    if idle?() do
      Logger.info("[AutoShutdown] node idle — stopping so Fly can scale to zero")
      # Graceful OTP shutdown: children (incl. Oban) drain in reverse start order.
      System.stop(0)
      {:noreply, state}
    else
      schedule_check(state.interval)
      {:noreply, state}
    end
  end

  defp schedule_check(interval), do: Process.send_after(self(), :check, interval)

  defp idle?, do: not connections?() and not oban_busy?()

  # Count live connections on Bandit's ThousandIsland listener — the Bandit
  # equivalent of Cowboy's `:ranch.procs/2`. An open browser (LiveView socket)
  # counts as a connection, so active players keep the node alive. If we can't
  # determine the count, err on the side of staying up.
  defp connections? do
    case listener_pid() do
      nil ->
        true

      pid ->
        case ThousandIsland.connection_pids(pid) do
          {:ok, []} -> false
          {:ok, _pids} -> true
          _ -> true
        end
    end
  end

  defp listener_pid do
    SanctumWeb.Endpoint
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {{SanctumWeb.Endpoint, :http}, pid, _, _} when is_pid(pid) -> pid
      _ -> nil
    end)
  rescue
    _ -> nil
  end

  defp oban_busy? do
    import Ecto.Query

    Sanctum.Repo.exists?(from(j in Oban.Job, where: j.state in ^@busy_states))
  rescue
    # If the DB check fails, keep the node up rather than risk killing work.
    _ -> true
  end
end
