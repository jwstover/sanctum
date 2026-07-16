defmodule Sanctum.CardSync.Server do
  @moduledoc """
  Runs card syncs detached from any LiveView and fans progress out over
  PubSub.

  The sync itself executes in a supervised `Task`, so the admin page can
  trigger a run and every connected client can watch it — or navigate away —
  without touching the sync. Only one sync runs at a time; latest progress is
  kept in state so a freshly-mounted LiveView shows a run already underway.
  """

  use GenServer

  alias Sanctum.CardSync

  @topic "card_sync"
  # Card upserts emit hundreds of progress events per second — cap broadcast
  # rate so LiveViews repaint at most ~10x/s. Phase changes always broadcast.
  @broadcast_interval_ms 100
  @max_failures_kept 50

  @aws_env ~w(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL_S3 BUCKET_NAME)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def subscribe, do: Phoenix.PubSub.subscribe(Sanctum.PubSub, @topic)

  @doc """
  Starts a sync (options as `Sanctum.CardSync.run/1`). Returns `:ok`,
  `{:error, :already_running}`, or `{:error, {:missing_env, vars}}` when
  image mirroring is requested without the bucket credentials.
  """
  def start_sync(opts \\ []), do: GenServer.call(__MODULE__, {:start_sync, opts})

  @doc "Latest sync state — also what PubSub delivers as `{:card_sync, state}`."
  def status, do: GenServer.call(__MODULE__, :status)

  @impl true
  def init(:ok) do
    {:ok, %{task_ref: nil, last_broadcast: 0, sync: idle_sync()}}
  end

  @impl true
  def handle_call({:start_sync, opts}, _from, %{task_ref: nil} = state) do
    case missing_env(opts) do
      [] ->
        {:reply, :ok, begin_sync(state, opts)}

      vars ->
        {:reply, {:error, {:missing_env, vars}}, state}
    end
  end

  def handle_call({:start_sync, _opts}, _from, state),
    do: {:reply, {:error, :already_running}, state}

  def handle_call(:status, _from, state), do: {:reply, state.sync, state}

  @impl true
  def handle_info({:progress, event}, state) do
    state = %{state | sync: apply_event(state.sync, event)}
    {:noreply, broadcast(state, broadcast_mode(event))}
  end

  def handle_info({ref, result}, %{task_ref: ref} = state) do
    Process.demonitor(ref, [:flush])
    sync = finish_sync(state.sync, result)
    emit_run_metrics(sync)
    {:noreply, broadcast(%{state | task_ref: nil, sync: sync}, :force)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
    Sentry.capture_message("card sync crashed: #{inspect(reason)}", level: :error)

    sync = %{
      state.sync
      | status: :error,
        phase: nil,
        current: nil,
        finished_at: DateTime.utc_now(),
        failures: add_failure(state.sync.failures, "sync crashed: #{inspect(reason)}")
    }

    emit_run_metrics(sync)
    {:noreply, broadcast(%{state | task_ref: nil, sync: sync}, :force)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp begin_sync(state, opts) do
    server = self()

    task =
      Task.Supervisor.async_nolink(Sanctum.TaskSupervisor, fn ->
        CardSync.run(Keyword.put(opts, :progress_fun, &send(server, {:progress, &1})))
      end)

    sync = %{idle_sync() | status: :running, phase: :fetching, started_at: DateTime.utc_now()}
    broadcast(%{state | task_ref: task.ref, sync: sync}, :force)
  end

  # Uploads need the bucket credentials; a missing var would otherwise crash
  # the task on the first image that isn't in the bucket yet.
  defp missing_env(opts) do
    if Keyword.get(opts, :images?, true) do
      Enum.filter(@aws_env, &(System.get_env(&1) in [nil, ""]))
    else
      []
    end
  end

  defp idle_sync do
    %{
      status: :idle,
      phase: nil,
      current: nil,
      index: 0,
      total: nil,
      data: %{synced: 0, failed: 0},
      images: %{uploaded: 0, skipped: 0, failed: 0},
      failures: [],
      started_at: nil,
      finished_at: nil
    }
  end

  defp apply_event(sync, {:packs_started, _}),
    do: %{sync | phase: :packs, index: 0, total: nil, current: "packs"}

  defp apply_event(sync, {:packs_done, %{count: count}}),
    do: %{sync | current: "#{count} products synced"}

  defp apply_event(sync, {:data_started, %{cards: cards}}),
    do: %{sync | phase: :data, index: 0, total: cards, current: nil}

  defp apply_event(sync, {:card, %{index: index, total: total, name: name, ok?: ok?}}) do
    data = Map.update!(sync.data, if(ok?, do: :synced, else: :failed), &(&1 + 1))
    %{sync | index: index, total: total, current: name, data: data}
  end

  defp apply_event(sync, {:data_done, %{synced: synced, failures: failures}}) do
    formatted =
      Enum.map(failures, fn {base_code, error} -> "card #{base_code}: #{inspect(error)}" end)

    %{
      sync
      | current: nil,
        data: %{synced: synced, failed: length(failures)},
        failures: Enum.reduce(formatted, sync.failures, &add_failure(&2, &1))
    }
  end

  defp apply_event(sync, {:images_started, %{total: total}}),
    do: %{sync | phase: :images, index: 0, total: total, current: nil}

  defp apply_event(sync, {:image, %{index: index, total: total, file: file, result: result}}) do
    key =
      case result do
        :uploaded -> :uploaded
        :error -> :failed
        _skipped_or_no_image -> :skipped
      end

    %{
      sync
      | index: index,
        total: total,
        current: file,
        images: Map.update!(sync.images, key, &(&1 + 1))
    }
  end

  defp apply_event(
         sync,
         {:images_done, %{uploaded: uploaded, skipped: skipped, failures: failures}}
       ) do
    formatted = Enum.map(failures, &"image: #{inspect(&1)}")

    %{
      sync
      | current: nil,
        images: %{uploaded: uploaded, skipped: skipped, failed: length(failures)},
        failures: Enum.reduce(formatted, sync.failures, &add_failure(&2, &1))
    }
  end

  defp apply_event(sync, {:dry_run, %{entries: entries, cards: cards, images: images}}),
    do: %{sync | current: "dry run: #{entries} entries -> #{cards} cards, #{images} images"}

  defp apply_event(sync, _event), do: sync

  defp finish_sync(sync, result) do
    status =
      case result do
        {:ok, _} -> :done
        {:error, _} -> :error
      end

    failures =
      case result do
        # Summary failures were already collected from the *_done events
        {:error, %{data: _}} -> sync.failures
        {:error, reason} -> add_failure(sync.failures, "fetch failed: #{inspect(reason)}")
        {:ok, _} -> sync.failures
      end

    %{
      sync
      | status: status,
        phase: nil,
        current: nil,
        finished_at: DateTime.utc_now(),
        failures: failures
    }
  end

  defp add_failure(failures, message), do: Enum.take([message | failures], @max_failures_kept)

  # One summary event per finished (or crashed) run, from the accumulated
  # snapshot. Wall-clock duration is fine here — runs are minutes long.
  defp emit_run_metrics(sync) do
    duration_ms =
      if sync.started_at && sync.finished_at do
        DateTime.diff(sync.finished_at, sync.started_at, :millisecond)
      else
        0
      end

    :telemetry.execute(
      [:sanctum, :card_sync, :run, :stop],
      %{
        duration_ms: duration_ms,
        synced: sync.data.synced,
        data_failed: sync.data.failed,
        uploaded: sync.images.uploaded,
        skipped: sync.images.skipped,
        images_failed: sync.images.failed
      },
      %{status: sync.status}
    )
  end

  defp broadcast_mode({:card, _}), do: :throttled
  defp broadcast_mode({:image, _}), do: :throttled
  defp broadcast_mode(_event), do: :force

  defp broadcast(state, mode) do
    now = System.monotonic_time(:millisecond)

    if mode == :force or now - state.last_broadcast >= @broadcast_interval_ms do
      Phoenix.PubSub.broadcast(Sanctum.PubSub, @topic, {:card_sync, state.sync})
      %{state | last_broadcast: now}
    else
      state
    end
  end
end
