defmodule SanctumWeb.EventLive.Index do
  @moduledoc false

  use SanctumWeb, :live_view

  alias Sanctum.Events

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Events")
     |> assign_events()}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    event = Events.get_event!(id, actor: user)
    :ok = Events.destroy_event(event, actor: user)

    {:noreply, socket |> put_flash(:info, "Event deleted") |> assign_events()}
  end

  defp assign_events(socket) do
    user = socket.assigns.current_user

    events =
      Events.list_events_for_user!(user.id,
        actor: user,
        load: [:total_players, :total_groups, :total_pods, :worlds_collide_target, :loki_hp_max]
      )

    assign(socket, :events, events)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:events}>
      <.header>
        Epic Multiplayer Events
        <:actions>
          <.button variant="primary" navigate={~p"/events/new"}>
            <.icon name="hero-plus" /> New Event
          </.button>
        </:actions>
      </.header>

      <p class="mb-6 max-w-2xl font-barlow text-base-content/70">
        Run an organizer dashboard for a massive multiplayer game of <span class="font-bold text-base-content">Loki: God of Lies</span>. Track Loki's
        hit points, the Worlds Collide doomsday clock, and the time limit across every
        group &mdash; the thresholds are derived from your roster automatically.
      </p>

      <div
        :if={@events == []}
        class="border-2 border-dashed border-neutral bg-base-200 p-8 text-center"
      >
        <p class="font-barlow-condensed text-lg uppercase tracking-[0.08em] text-base-content/60">
          No events yet
        </p>
        <p class="mt-1 font-barlow text-base-content/50">
          Create one to build your roster and start tracking.
        </p>
      </div>

      <div :if={@events != []} class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <.panel :for={event <- @events} class="flex flex-col gap-3 p-4">
          <div class="flex items-start justify-between gap-2">
            <h2 class="font-anton text-xl uppercase leading-none">{event.name}</h2>
            <.status_chip status={event.status} />
          </div>

          <dl class="grid grid-cols-3 gap-2 font-barlow-condensed">
            <.stat_cell label="Players" value={event.total_players || 0} />
            <.stat_cell label="Groups" value={event.total_groups || 0} />
            <.stat_cell label="Pods" value={event.total_pods || 0} />
          </dl>

          <div class="mt-auto flex gap-2">
            <.button
              :if={event.status == :setup}
              variant="ghost"
              navigate={~p"/events/#{event.id}/setup"}
              class="flex-1"
            >
              Set up roster
            </.button>
            <.button
              :if={event.status != :setup}
              variant="primary"
              navigate={~p"/events/#{event.id}"}
              class="flex-1"
            >
              Open dashboard
            </.button>
            <.button
              variant="icon"
              phx-click="delete"
              phx-value-id={event.id}
              data-confirm={"Delete #{event.name}? This cannot be undone."}
              aria-label="Delete event"
            >
              <.icon name="hero-trash" class="size-4" />
            </.button>
          </div>
        </.panel>
      </div>
    </Layouts.app>
    """
  end

  attr :status, :atom, required: true

  defp status_chip(assigns) do
    ~H"""
    <span class={[
      "border-2 border-neutral px-2 py-0.5 font-barlow-condensed text-xs font-bold uppercase tracking-[0.1em]",
      @status == :setup && "bg-base-300 text-base-content/70",
      @status == :running && "bg-primary text-primary-content",
      @status == :complete && "bg-success text-neutral"
    ]}>
      {@status}
    </span>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp stat_cell(assigns) do
    ~H"""
    <div class="border-2 border-neutral bg-base-300 px-2 py-1 text-center">
      <dt class="font-ibm-mono text-[0.6rem] uppercase tracking-[0.15em] text-base-content/50">
        {@label}
      </dt>
      <dd class="font-anton text-lg leading-none">{@value}</dd>
    </div>
    """
  end
end
