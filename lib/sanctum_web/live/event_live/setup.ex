defmodule SanctumWeb.EventLive.Setup do
  @moduledoc """
  Piece 1 of the organizer dashboard: build the roster (pods → groups → player
  counts + per-group difficulty). The rulebook thresholds are derived live from
  the roster so the organizer sees exactly what the clocks will start at before
  committing.
  """
  use SanctumWeb, :live_view

  alias Sanctum.Events

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  @load [
    :total_players,
    :total_groups,
    :total_pods,
    :loki_hp_max,
    :loki_flip_threshold,
    :worlds_collide_target,
    pods: [:groups]
  ]

  def mount(%{"id" => id}, _session, socket) do
    {:ok, assign_event(socket, id)}
  end

  def handle_event("add_pod", _params, socket) do
    event = socket.assigns.event
    user = socket.assigns.current_user
    name = "Pod #{<<?A + length(event.pods)::utf8>>}"

    {:ok, _pod} = Events.create_pod(%{name: name, event_id: event.id}, actor: user)

    {:noreply, reload(socket)}
  end

  def handle_event("delete_pod", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    pod = Enum.find(socket.assigns.event.pods, &(&1.id == id))
    if pod, do: Events.destroy_pod!(pod, actor: user)

    {:noreply, reload(socket)}
  end

  def handle_event("add_group", %{"pod-id" => pod_id}, socket) do
    user = socket.assigns.current_user
    name = "Group #{next_group_number(socket.assigns.event)}"

    {:ok, _group} =
      Events.create_group(%{name: name, pod_id: pod_id, player_count: 1}, actor: user)

    {:noreply, reload(socket)}
  end

  def handle_event("delete_group", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    {:ok, group} = Events.get_group(id, actor: user)
    Events.destroy_group!(group, actor: user)

    {:noreply, reload(socket)}
  end

  def handle_event("adjust_players", %{"id" => id, "amount" => amount}, socket) do
    user = socket.assigns.current_user
    {:ok, group} = Events.get_group(id, actor: user)
    new_count = max(1, min(4, group.player_count + String.to_integer(amount)))
    Events.update_group!(group, %{player_count: new_count}, actor: user)

    {:noreply, reload(socket)}
  end

  def handle_event("set_difficulty", %{"id" => id, "difficulty" => difficulty}, socket) do
    user = socket.assigns.current_user
    {:ok, group} = Events.get_group(id, actor: user)
    Events.update_group!(group, %{difficulty: String.to_existing_atom(difficulty)}, actor: user)

    {:noreply, reload(socket)}
  end

  def handle_event("start", _params, socket) do
    event = socket.assigns.event
    user = socket.assigns.current_user

    if (event.total_players || 0) < 1 do
      {:noreply, put_flash(socket, :error, "Add at least one group with players first.")}
    else
      {:ok, _started} = Events.start_event(event, actor: user)
      {:noreply, push_navigate(socket, to: ~p"/events/#{event.id}")}
    end
  end

  defp assign_event(socket, id) do
    user = socket.assigns.current_user

    case Events.get_event(id, actor: user, load: @load) do
      {:ok, %{user_id: uid} = event} when uid == user.id ->
        socket
        |> assign(:page_title, "#{event.name} — Setup")
        |> assign(:event, event)

      _ ->
        socket
        |> put_flash(:error, "Event not found")
        |> push_navigate(to: ~p"/events")
    end
  end

  defp reload(socket) do
    assign_event(socket, socket.assigns.event.id)
  end

  # Oldest first, newest last (deterministic — DateTime needs its own comparator;
  # the default term order sorts the struct's fields alphabetically, not in time).
  defp pods(event), do: Enum.sort_by(event.pods, & &1.inserted_at, DateTime)
  defp groups(pod), do: Enum.sort_by(pod.groups, & &1.inserted_at, DateTime)

  # Next "Group N" number, unique across the whole event (all pods). Uses the
  # highest existing trailing number + 1 so it stays unique after deletions.
  defp next_group_number(event) do
    event.pods
    |> Enum.flat_map(& &1.groups)
    |> Enum.map(&trailing_number(&1.name))
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp trailing_number(name) do
    case Regex.run(~r/(\d+)\s*$/, name) do
      [_, digits] -> String.to_integer(digits)
      _ -> 0
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:events}>
      <.header>
        {@event.name} <span class="text-base-content/40">— Roster</span>
        <:actions>
          <.button variant="ghost" navigate={~p"/events"}>Back</.button>
          <.button variant="primary" phx-click={open_confirm("confirm-start")}>
            Start event
          </.button>
          <.confirm_dialog
            id="confirm-start"
            message="Lock the roster and start the clocks?"
            confirm_label="Start event"
            phx-click="start"
          />
        </:actions>
      </.header>

      <.thresholds_panel event={@event} />

      <div class="mt-6 flex flex-wrap items-center justify-between gap-3">
        <h2 class="font-anton text-2xl uppercase">Pods &amp; Groups</h2>
        <.button variant="ghost" phx-click="add_pod"><.icon name="hero-plus" /> Add pod</.button>
      </div>

      <div
        :if={@event.pods == []}
        class="mt-4 border-2 border-dashed border-neutral bg-base-200 p-6 text-center font-barlow text-base-content/60"
      >
        No pods yet. Add a pod, then add the groups inside it.
      </div>

      <div class="mt-4 space-y-4">
        <.panel :for={pod <- pods(@event)} class="p-4">
          <div class="flex items-center justify-between gap-2 border-b-2 border-neutral pb-2">
            <h3 class="font-anton text-xl uppercase">{pod.name}</h3>
            <div class="flex gap-2">
              <.button variant="ghost" phx-click="add_group" phx-value-pod-id={pod.id}>
                <.icon name="hero-plus" class="size-4" /> Add group
              </.button>
              <.button
                variant="icon"
                phx-click={open_confirm("confirm-delete-pod-#{pod.id}")}
                aria-label="Delete pod"
              >
                <.icon name="hero-trash" class="size-4" />
              </.button>
              <.confirm_dialog
                id={"confirm-delete-pod-#{pod.id}"}
                message={"Delete #{pod.name} and its groups?"}
                confirm_label="Delete pod"
                phx-click="delete_pod"
                phx-value-id={pod.id}
              />
            </div>
          </div>

          <p :if={pod.groups == []} class="py-3 font-barlow text-sm text-base-content/50">
            No groups in this pod yet.
          </p>

          <ul class="divide-y-2 divide-neutral/40">
            <li :for={group <- groups(pod)} class="flex flex-wrap items-center gap-3 py-3">
              <span class="min-w-[6rem] font-barlow-condensed font-bold uppercase tracking-[0.05em]">
                {group.name}
              </span>

              <div class="flex items-center gap-1.5">
                <span class="font-ibm-mono text-[0.6rem] uppercase tracking-[0.15em] text-base-content/50">
                  Players
                </span>
                <.stepper
                  id={group.id}
                  event="adjust_players"
                  value={group.player_count}
                  min={1}
                  max={4}
                />
              </div>

              <div class="flex overflow-hidden border-2 border-neutral">
                <button
                  :for={diff <- [:standard, :expert]}
                  type="button"
                  phx-click="set_difficulty"
                  phx-value-id={group.id}
                  phx-value-difficulty={diff}
                  class={[
                    "px-2.5 py-1 font-barlow-condensed text-xs font-bold uppercase tracking-[0.08em] cursor-pointer",
                    (group.difficulty == diff && "bg-primary text-primary-content") ||
                      "bg-base-300 text-base-content/60 hover:text-white"
                  ]}
                >
                  {diff}
                </button>
              </div>

              <button
                type="button"
                phx-click="delete_group"
                phx-value-id={group.id}
                aria-label="Delete group"
                class="ml-auto flex size-8 cursor-pointer items-center justify-center border-2 border-neutral bg-base-100 text-base-content/60 hover:text-error"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </li>
          </ul>
        </.panel>
      </div>
    </Layouts.app>
    """
  end

  attr :event, :map, required: true

  defp thresholds_panel(assigns) do
    ~H"""
    <.panel class="bg-halftone p-4">
      <p class="mb-3 font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/50">
        Derived from roster
      </p>
      <dl class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
        <.threshold label="Total players" value={@event.total_players || 0} />
        <.threshold label="Total groups" value={@event.total_groups || 0} />
        <.threshold label="Loki HP" value={@event.loki_hp_max || 0} hint="20 × players" accent />
        <.threshold label="Flip at" value={@event.loki_flip_threshold || 0} hint="10 × players" />
        <.threshold
          label="Worlds Collide"
          value={@event.worlds_collide_target || 0}
          hint="2 × groups · lose"
        />
      </dl>
    </.panel>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :hint, :string, default: nil
  attr :accent, :boolean, default: false

  defp threshold(assigns) do
    ~H"""
    <div class={[
      "border-2 border-neutral px-3 py-2",
      (@accent && "bg-primary text-primary-content") || "bg-base-300"
    ]}>
      <dt class="font-ibm-mono text-[0.6rem] uppercase tracking-[0.15em] opacity-60">{@label}</dt>
      <dd class="font-anton text-2xl leading-none">{@value}</dd>
      <p
        :if={@hint}
        class="mt-0.5 font-barlow-condensed text-[0.65rem] uppercase tracking-[0.08em] opacity-50"
      >
        {@hint}
      </p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :value, :integer, required: true
  attr :min, :integer, default: nil
  attr :max, :integer, default: nil

  defp stepper(assigns) do
    ~H"""
    <div class="flex items-center border-2 border-neutral">
      <button
        type="button"
        phx-click={@event}
        phx-value-id={@id}
        phx-value-amount="-1"
        disabled={@min && @value <= @min}
        class="flex size-7 cursor-pointer items-center justify-center bg-base-300 text-base-content hover:text-white disabled:opacity-30 disabled:cursor-not-allowed"
        aria-label="Decrease"
      >
        <.icon name="hero-minus" class="size-3.5" />
      </button>
      <span class="min-w-[2rem] bg-base-100 py-0.5 text-center font-anton text-lg leading-none">
        {@value}
      </span>
      <button
        type="button"
        phx-click={@event}
        phx-value-id={@id}
        phx-value-amount="1"
        disabled={@max && @value >= @max}
        class="flex size-7 cursor-pointer items-center justify-center bg-base-300 text-base-content hover:text-white disabled:opacity-30 disabled:cursor-not-allowed"
        aria-label="Increase"
      >
        <.icon name="hero-plus" class="size-3.5" />
      </button>
    </div>
    """
  end
end
