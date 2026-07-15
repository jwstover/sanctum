defmodule Sanctum.DeckSync.Monitor do
  @moduledoc """
  Holds the latest decklist-sync progress and fans it out over PubSub.

  Unlike the interactive card sync, the deck sync runs headless inside an Oban
  worker (`Sanctum.Decks.DecklistSyncWorker`). That worker passes `report/1` as
  its `progress_fun`, so every progress event flows into this singleton
  GenServer, which folds it into a running snapshot and broadcasts the snapshot
  (throttled) to the `"deck_sync"` topic. The admin dashboard subscribes for
  live updates and calls `status/0` on mount to render a run already underway —
  or the outcome of the last one, since the snapshot is retained between runs.
  """

  use GenServer

  require Logger

  @topic "deck_sync"

  # A single day can import dozens of decks; cap the broadcast rate so LiveViews
  # repaint at most ~10x/s. Lifecycle events (started/date/done/error) always
  # broadcast so the dashboard never lags a phase change.
  @broadcast_interval_ms 100
  @max_failures_kept 50

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def subscribe, do: Phoenix.PubSub.subscribe(Sanctum.PubSub, @topic)

  @doc "Latest sync snapshot — also what PubSub delivers as `{:deck_sync, snapshot}`."
  def status, do: GenServer.call(__MODULE__, :status)

  @doc """
  Progress sink for `Sanctum.DeckSync.run/1`. Fire-and-forget so a slow or
  restarting monitor never stalls the sync.
  """
  def report(event), do: GenServer.cast(__MODULE__, {:progress, event})

  @impl true
  def init(:ok), do: {:ok, %{last_broadcast: 0, sync: idle_sync()}}

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.sync, state}

  @impl true
  def handle_cast({:progress, event}, state) do
    log(event)
    state = %{state | sync: apply_event(state.sync, event)}
    {:noreply, broadcast(state, broadcast_mode(event))}
  end

  defp idle_sync do
    %{
      status: :idle,
      from: nil,
      to: nil,
      current_date: nil,
      current_deck: nil,
      days_total: nil,
      days_done: 0,
      imported: 0,
      failed: 0,
      failures: [],
      started_at: nil,
      finished_at: nil
    }
  end

  defp apply_event(_sync, {:started, %{from: from, to: to, days: days}}) do
    %{idle_sync() | status: :running, from: from, to: to, days_total: days, started_at: now()}
  end

  defp apply_event(sync, {:deck, %{date: date, name: name, ok?: ok?}}) do
    %{
      sync
      | current_date: date,
        current_deck: name,
        imported: sync.imported + if(ok?, do: 1, else: 0),
        failed: sync.failed + if(ok?, do: 0, else: 1)
    }
  end

  defp apply_event(sync, {:date, %{date: date}}) do
    %{sync | current_date: date, current_deck: nil, days_done: sync.days_done + 1}
  end

  defp apply_event(sync, {:date_error, %{date: date, reason: reason}}) do
    %{
      sync
      | current_date: date,
        current_deck: nil,
        days_done: sync.days_done + 1,
        failures: add_failure(sync.failures, "#{date}: fetch failed: #{inspect(reason)}")
    }
  end

  defp apply_event(sync, {:done, %{imported: imported, failed: failed} = summary}) do
    %{
      sync
      | status: if(summary[:halted], do: :error, else: :done),
        current_date: nil,
        current_deck: nil,
        imported: imported,
        failed: failed,
        finished_at: now()
    }
  end

  defp apply_event(sync, _event), do: sync

  defp add_failure(failures, message), do: Enum.take([message | failures], @max_failures_kept)

  # Mirror the CLI logging the worker loses by routing progress here instead of
  # `Sanctum.DeckSync`'s default logger. Per-deck events are intentionally silent
  # (too chatty for the logs); the dashboard is where you watch them tick by.
  defp log({:started, %{from: from, to: to, days: days}}),
    do: Logger.info("Deck sync: #{from}..#{to} (#{days} days)")

  defp log({:date, %{date: date, imported: imported, failed: failed}}),
    do: Logger.info("Deck sync #{date}: #{imported} imported, #{failed} failed")

  defp log({:date_error, %{date: date, reason: reason}}),
    do: Logger.warning("Deck sync #{date}: fetch failed: #{inspect(reason)}")

  defp log({:done, %{halted: %{date: date, reason: reason}} = s}),
    do:
      Logger.warning(
        "Deck sync halted at #{date} (#{inspect(reason)}): #{s.imported} imported, #{s.failed} failed"
      )

  defp log({:done, %{days: days, imported: imported, failed: failed}}),
    do: Logger.info("Deck sync done: #{days} days, #{imported} imported, #{failed} failed")

  defp log(_event), do: :ok

  defp broadcast_mode({:deck, _}), do: :throttled
  defp broadcast_mode(_event), do: :force

  defp broadcast(state, mode) do
    now = System.monotonic_time(:millisecond)

    if mode == :force or now - state.last_broadcast >= @broadcast_interval_ms do
      Phoenix.PubSub.broadcast(Sanctum.PubSub, @topic, {:deck_sync, state.sync})
      %{state | last_broadcast: now}
    else
      state
    end
  end

  defp now, do: DateTime.utc_now()
end
