defmodule SanctumWeb.EventLive.Show do
  @moduledoc """
  Piece 2 of the organizer dashboard: the live tracking board.

  Renders the three global clocks (Loki's HP, Worlds Collide threat, the time
  limit) plus per-pod Mangog / Door counters and a per-group status grid. All
  mutations broadcast over PubSub so multiple organizers — and a projector view
  — stay in sync in real time.
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
    pods: [groups: [:mangog_hp_max, :door_threat_max]]
  ]

  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sanctum.PubSub, topic(id))
      :timer.send_interval(1000, self(), :tick)
    end

    {:ok, socket |> assign(:now, DateTime.utc_now()) |> assign_event(id)}
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(:outcome, outcome(assigns.event))
      |> assign(:remaining, seconds_remaining(assigns.event, assigns.now))
      |> assign(:endgame, worlds_collide_full?(assigns.event))

    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:events}>
      <.header>
        {@event.name}
        <:actions>
          <.button variant="ghost" navigate={~p"/events"}>Back</.button>
          <.button variant="ghost" navigate={~p"/events/#{@event.id}/setup"}>Edit roster</.button>
        </:actions>
      </.header>

      <.banner outcome={@outcome} />

      <div class="grid gap-4 lg:grid-cols-[1fr_auto]">
        <.loki_panel event={@event} />
        <.timer_panel remaining={@remaining} limit={@event.time_limit_minutes} />
      </div>

      <div class="mt-4">
        <.worlds_collide_panel event={@event} />
      </div>

      <div class="mt-6">
        <h2 class="mb-3 font-anton text-2xl uppercase">Pods &amp; Groups</h2>
        <div class="space-y-5">
          <section
            :for={pod <- pods(@event)}
            class="border-2 border-neutral bg-base-100 shadow-comic-sm"
          >
            <div class="flex items-center justify-between gap-2 border-b-2 border-neutral bg-base-300 bg-halftone px-3 py-2">
              <h3 class="font-anton text-lg uppercase leading-none">{pod.name}</h3>
              <span class="font-barlow-condensed text-xs uppercase tracking-[0.08em] text-base-content/50">
                {pod_summary(pod)}
              </span>
            </div>

            <p
              :if={pod.groups == []}
              class="p-3 font-barlow text-sm text-base-content/50"
            >
              No groups in this pod.
            </p>

            <div class="grid gap-3 p-3 sm:grid-cols-2 lg:grid-cols-3">
              <.group_card :for={group <- pod_groups(pod)} group={group} endgame={@endgame} />
            </div>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # --- Loki, God of Lies -----------------------------------------------------

  def handle_event("record_damage", %{"amount" => amount}, socket) do
    case parse_int(amount) do
      {:ok, n} when n != 0 -> adjust_loki(socket, -abs(n))
      _ -> {:noreply, socket}
    end
  end

  def handle_event("loki_delta", %{"amount" => amount}, socket) do
    adjust_loki(socket, String.to_integer(amount))
  end

  # --- Worlds Collide --------------------------------------------------------

  def handle_event("worlds_collide_delta", %{"amount" => amount}, socket) do
    adjust_worlds_collide(socket, String.to_integer(amount))
  end

  # --- Groups: Mangog / Door -------------------------------------------------

  def handle_event("toggle_mangog", %{"id" => id}, socket) do
    group = find_group(socket, id)

    # Entering play seeds full HP (10 × groups in the pod).
    Events.update_group!(
      group,
      %{mangog_active: !group.mangog_active, mangog_hp: group.mangog_hp_max || 0},
      actor: actor(socket)
    )

    {:noreply, reload_and_broadcast(socket)}
  end

  def handle_event("mangog_delta", %{"id" => id, "amount" => amount}, socket) do
    group = find_group(socket, id)
    Events.adjust_mangog_hp!(group, %{amount: String.to_integer(amount)}, actor: actor(socket))
    {:noreply, reload_and_broadcast(socket)}
  end

  def handle_event("toggle_door", %{"id" => id}, socket) do
    group = find_group(socket, id)

    # Enters play with full threat (7 × groups), thwarted down toward 0.
    Events.update_group!(
      group,
      %{door_active: !group.door_active, door_threat: group.door_threat_max || 0},
      actor: actor(socket)
    )

    {:noreply, reload_and_broadcast(socket)}
  end

  def handle_event("door_delta", %{"id" => id, "amount" => amount}, socket) do
    group = find_group(socket, id)
    Events.adjust_door_threat!(group, %{amount: String.to_integer(amount)}, actor: actor(socket))
    {:noreply, reload_and_broadcast(socket)}
  end

  # --- Groups ----------------------------------------------------------------

  # Both group-level triggers place 1 threat on Worlds Collide: a group's
  # Mischief and Mayhem completing, and an identity that would be defeated
  # (which instead flips to alter-ego at 1 HP — it is never removed).
  def handle_event("scheme_completed", _params, socket), do: adjust_worlds_collide(socket, 1)
  def handle_event("identity_defeated", _params, socket), do: adjust_worlds_collide(socket, 1)

  def handle_event("toggle_phase_ended", %{"id" => id}, socket) do
    group = find_group(socket, id)
    new_status = if group.status == :phases_ended, do: :playing, else: :phases_ended
    Events.update_group!(group, %{status: new_status}, actor: actor(socket))
    {:noreply, reload_and_broadcast(socket)}
  end

  # --- Live sync + timer -----------------------------------------------------

  def handle_info(:event_updated, socket) do
    {:noreply, reload(socket)}
  end

  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :now, DateTime.utc_now())}
  end

  # --- Helpers ---------------------------------------------------------------

  defp adjust_loki(socket, amount) do
    Events.adjust_loki_hp!(socket.assigns.event, %{amount: amount}, actor: actor(socket))
    {:noreply, reload_and_broadcast(socket)}
  end

  defp adjust_worlds_collide(socket, amount) do
    Events.adjust_worlds_collide!(socket.assigns.event, %{amount: amount}, actor: actor(socket))
    {:noreply, reload_and_broadcast(socket)}
  end

  defp actor(socket), do: socket.assigns.current_user
  defp topic(id), do: "event:#{id}"

  defp find_group(socket, id) do
    socket.assigns.event.pods
    |> Enum.flat_map(& &1.groups)
    |> Enum.find(&(&1.id == id))
  end

  defp parse_int(str) do
    case Integer.parse(String.trim(str || "")) do
      {n, _} -> {:ok, n}
      :error -> :error
    end
  end

  defp assign_event(socket, id) do
    user = socket.assigns.current_user

    case Events.get_event(id, actor: user, load: @load) do
      {:ok, %{user_id: uid, status: :setup}} when uid == user.id ->
        push_navigate(socket, to: ~p"/events/#{id}/setup")

      {:ok, %{user_id: uid} = event} when uid == user.id ->
        socket
        |> assign(:page_title, event.name)
        |> assign(:event, event)

      _ ->
        socket
        |> put_flash(:error, "Event not found")
        |> push_navigate(to: ~p"/events")
    end
  end

  defp reload(socket), do: assign_event(socket, socket.assigns.event.id)

  defp reload_and_broadcast(socket) do
    Phoenix.PubSub.broadcast_from(
      Sanctum.PubSub,
      self(),
      topic(socket.assigns.event.id),
      :event_updated
    )

    reload(socket)
  end

  # --- Derived view state ----------------------------------------------------

  defp pods(event), do: Enum.sort_by(event.pods, & &1.inserted_at, DateTime)

  # A pod's groups, oldest first / newest last.
  defp pod_groups(pod), do: Enum.sort_by(pod.groups, & &1.inserted_at, DateTime)

  defp pod_summary(pod) do
    n = length(pod.groups)
    players = pod.groups |> Enum.map(& &1.player_count) |> Enum.sum()
    "#{n} #{pluralize(n, "group")} · #{players} #{pluralize(players, "player")}"
  end

  defp pluralize(1, word), do: word
  defp pluralize(_, word), do: word <> "s"

  defp worlds_collide_full?(event) do
    target = event.worlds_collide_target || 0
    target > 0 and event.worlds_collide_threat >= target
  end

  defp outcome(event) do
    groups = Enum.flat_map(pods(event), & &1.groups)
    wc_full = worlds_collide_full?(event)
    all_ended = groups != [] and Enum.all?(groups, &(&1.status == :phases_ended))

    cond do
      event.loki_hp == 0 -> :won
      wc_full and all_ended -> :lost
      wc_full -> :verge
      event.loki_flipped -> :flipped
      true -> :none
    end
  end

  defp seconds_remaining(%{started_at: nil}, _now), do: nil

  defp seconds_remaining(event, now) do
    ends_at = DateTime.add(event.started_at, event.time_limit_minutes * 60, :second)
    max(0, DateTime.diff(ends_at, now, :second))
  end

  defp format_clock(nil), do: "--:--"

  defp format_clock(total) do
    h = div(total, 3600)
    m = total |> rem(3600) |> div(60)
    s = rem(total, 60)

    if h > 0 do
      "#{h}:#{pad(m)}:#{pad(s)}"
    else
      "#{pad(m)}:#{pad(s)}"
    end
  end

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")

  defp pct(_value, 0), do: 0
  defp pct(_value, nil), do: 0
  defp pct(value, max), do: min(100, round(value / max * 100))

  defp classes(list), do: list |> Enum.filter(& &1) |> Enum.join(" ")

  # --- View components -------------------------------------------------------

  attr :outcome, :atom, required: true

  defp banner(%{outcome: :none} = assigns), do: ~H""

  defp banner(assigns) do
    ~H"""
    <div class={[
      "mb-4 flex items-center gap-3 border-2 border-neutral px-4 py-3 shadow-comic-sm",
      @outcome == :won && "bg-success text-neutral",
      @outcome == :lost && "bg-error text-white",
      @outcome == :verge && "bg-error/20 text-error",
      @outcome == :flipped && "bg-primary/20 text-primary"
    ]}>
      <.icon
        name={if(@outcome == :won, do: "hero-trophy", else: "hero-exclamation-triangle")}
        class="size-6 flex-none"
      />
      <p class="font-barlow-condensed text-lg font-bold uppercase tracking-[0.06em]">
        {banner_text(@outcome)}
      </p>
    </div>
    """
  end

  defp banner_text(:won), do: "Loki, God of Lies is defeated — all players win!"
  defp banner_text(:lost), do: "Worlds Collide is complete and all phases ended — players lose."

  defp banner_text(:verge),
    do: "Worlds Collide has reached its target — players are on the verge of losing!"

  defp banner_text(:flipped),
    do: "Loki has flipped — pause all groups and apply Intense / Total Focus."

  attr :event, :map, required: true

  defp loki_panel(assigns) do
    assigns =
      assign(assigns, :fill, pct(assigns.event.loki_hp || 0, assigns.event.loki_hp_max))

    ~H"""
    <.panel class="p-4 sm:p-5">
      <div class="flex items-end justify-between gap-3">
        <div>
          <p class="font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/50">
            Loki, God of Lies
          </p>
          <p class="font-anton text-4xl leading-none">
            {@event.loki_hp || 0}<span class="text-2xl text-base-content/40">/{@event.loki_hp_max || 0} HP</span>
          </p>
        </div>
        <span
          :if={@event.loki_flipped}
          class="border-2 border-neutral bg-primary px-2 py-0.5 font-barlow-condensed text-xs font-bold uppercase tracking-[0.1em] text-primary-content"
        >
          Flipped
        </span>
      </div>

      <%!-- HP bar: counts DOWN. Flip line sits at 50% (10×players of 20×players). --%>
      <div class="relative mt-3 h-8 border-2 border-neutral bg-base-100">
        <div class="h-full bg-error transition-all duration-300" style={"width: #{@fill}%"}></div>
        <.bar_marker at={50} label="FLIP / ½" />
        <.bar_marker at={25} label="¼" />
      </div>

      <div class="mt-4 flex flex-wrap items-end gap-4">
        <form phx-submit="record_damage" class="flex items-end gap-2">
          <div class="flex flex-col gap-1">
            <label class="font-ibm-mono text-[0.6rem] uppercase tracking-[0.15em] text-base-content/50">
              Record damage
            </label>
            <input
              type="number"
              name="amount"
              min="1"
              placeholder="e.g. 20"
              class="w-28 bg-black border-[2.5px] border-line px-3 py-2 font-anton text-lg text-base-content outline-none focus:border-primary"
            />
          </div>
          <.button variant="primary" type="submit">Deal to Loki</.button>
        </form>

        <div class="flex items-center gap-1.5">
          <span class="font-ibm-mono text-[0.6rem] uppercase tracking-[0.15em] text-base-content/50">
            Correct
          </span>
          <.delta_button event="loki_delta" amount="-1" label="-1" />
          <.delta_button event="loki_delta" amount="1" label="+1" />
          <.delta_button event="loki_delta" amount="10" label="+10" />
        </div>
      </div>
    </.panel>
    """
  end

  attr :remaining, :integer, required: true
  attr :limit, :integer, required: true

  defp timer_panel(assigns) do
    assigns =
      assign(
        assigns,
        :class,
        classes([
          "flex flex-col items-center justify-center p-4 sm:min-w-[12rem]",
          assigns.remaining && assigns.remaining <= 300 && "bg-error/15"
        ])
      )

    ~H"""
    <.panel class={@class}>
      <p class="font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/50">
        Time left
      </p>
      <p class="font-anton text-5xl leading-none tabular-nums">{format_clock(@remaining)}</p>
      <p class="mt-1 font-barlow-condensed text-xs uppercase tracking-[0.08em] text-base-content/40">
        of {@limit} min
      </p>
    </.panel>
    """
  end

  attr :event, :map, required: true

  defp worlds_collide_panel(assigns) do
    assigns =
      assign(
        assigns,
        :fill,
        pct(assigns.event.worlds_collide_threat, assigns.event.worlds_collide_target)
      )

    ~H"""
    <.panel class="p-4 sm:p-5">
      <div class="flex items-end justify-between gap-3">
        <div>
          <p class="font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/50">
            Worlds Collide — doomsday clock
          </p>
          <p class="font-anton text-3xl leading-none">
            {@event.worlds_collide_threat}<span class="text-xl text-base-content/40">/{@event.worlds_collide_target ||
              0} threat</span>
          </p>
        </div>
      </div>

      <%!-- Threat bar: counts UP toward the target (loss). --%>
      <div class="relative mt-3 h-8 border-2 border-neutral bg-base-100">
        <div class="h-full bg-warning transition-all duration-300" style={"width: #{@fill}%"}></div>
        <.bar_marker at={50} label="½" />
      </div>

      <div class="mt-4 flex flex-wrap items-center gap-2">
        <span class="font-ibm-mono text-[0.6rem] uppercase tracking-[0.15em] text-base-content/50">
          Adjust threat
        </span>
        <.delta_button event="worlds_collide_delta" amount="-1" label="-1" />
        <.delta_button event="worlds_collide_delta" amount="1" label="+1" />
        <span class="ml-1 font-barlow text-xs text-base-content/40">
          (threat is added from the group cards below)
        </span>
      </div>
    </.panel>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, required: true
  attr :toggle, :string, required: true
  attr :value, :integer, required: true
  attr :max, :integer, required: true
  attr :unit, :string, required: true
  attr :event, :string, required: true

  defp card_counter(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-2 border-2 border-neutral bg-base-300 px-3 py-2">
      <div class="min-w-0">
        <p class="font-barlow-condensed font-bold uppercase tracking-[0.05em]">{@label}</p>
        <p :if={@active} class="font-anton text-xl leading-none">
          {@value}<span class="text-sm text-base-content/40">/{@max} {@unit}</span>
        </p>
      </div>
      <div :if={@active} class="flex items-center gap-1.5">
        <.delta_button event={@event} id={@id} amount="-1" label="-1" />
        <.delta_button event={@event} id={@id} amount="1" label="+1" />
        <button
          type="button"
          phx-click={@toggle}
          phx-value-id={@id}
          class="font-barlow-condensed text-xs uppercase tracking-[0.08em] text-base-content/40 hover:text-error cursor-pointer"
        >
          clear
        </button>
      </div>
      <button
        :if={!@active}
        type="button"
        phx-click={@toggle}
        phx-value-id={@id}
        class="cursor-pointer border-2 border-neutral bg-base-100 px-2.5 py-1 font-barlow-condensed text-xs font-bold uppercase tracking-[0.08em] hover:text-white"
      >
        In play
      </button>
    </div>
    """
  end

  attr :group, :map, required: true
  attr :endgame, :boolean, required: true

  defp group_card(assigns) do
    assigns =
      assign(
        assigns,
        :class,
        classes([
          "p-3",
          assigns.group.status == :phases_ended && "border-warning"
        ])
      )

    ~H"""
    <.panel class={@class}>
      <div class="flex items-center justify-between gap-2">
        <h3 class="min-w-0 truncate font-barlow-condensed text-lg font-bold uppercase tracking-[0.05em] leading-none">
          {@group.name}
        </h3>
        <span class={[
          "border-2 border-neutral px-1.5 py-0.5 font-barlow-condensed text-[0.65rem] font-bold uppercase tracking-[0.08em]",
          (@group.difficulty == :expert && "bg-error text-white") ||
            "bg-base-300 text-base-content/70"
        ]}>
          {@group.difficulty}
        </span>
      </div>

      <p class="mt-1 font-barlow-condensed text-xs uppercase tracking-[0.06em] text-base-content/40">
        {@group.player_count} {if @group.player_count == 1, do: "player", else: "players"}
      </p>

      <%!-- The two per-group triggers that each add 1 threat to Worlds Collide. --%>
      <div class="mt-3 grid grid-cols-2 gap-2">
        <button
          type="button"
          phx-click="scheme_completed"
          class="cursor-pointer border-2 border-neutral bg-base-300 px-2 py-1.5 font-barlow-condensed text-[0.7rem] font-bold uppercase leading-tight tracking-[0.04em] hover:text-white"
        >
          M&amp;M completed <span class="text-base-content/50">(+1 WC)</span>
        </button>
        <button
          type="button"
          phx-click="identity_defeated"
          class="cursor-pointer border-2 border-neutral bg-base-300 px-2 py-1.5 font-barlow-condensed text-[0.7rem] font-bold uppercase leading-tight tracking-[0.04em] hover:text-white"
        >
          Identity down <span class="text-base-content/50">(+1 WC)</span>
        </button>
      </div>

      <%!-- Endgame only: mark this group's final player phase as ended. --%>
      <button
        :if={@endgame}
        type="button"
        phx-click="toggle_phase_ended"
        phx-value-id={@group.id}
        class={[
          "mt-2 w-full cursor-pointer border-2 border-neutral px-2 py-1.5 font-barlow-condensed text-[0.7rem] font-bold uppercase tracking-[0.06em]",
          (@group.status == :phases_ended && "bg-warning text-neutral") ||
            "bg-base-300 text-base-content hover:text-white"
        ]}
      >
        {if @group.status == :phases_ended, do: "✓ Final phase ended", else: "Mark final phase ended"}
      </button>

      <div class="mt-3 space-y-2 border-t-2 border-neutral/40 pt-3">
        <.card_counter
          id={@group.id}
          label="The Mangog"
          active={@group.mangog_active}
          toggle="toggle_mangog"
          value={@group.mangog_hp}
          max={@group.mangog_hp_max}
          unit="HP"
          event="mangog_delta"
        />
        <.card_counter
          id={@group.id}
          label="Door Between Worlds"
          active={@group.door_active}
          toggle="toggle_door"
          value={@group.door_threat}
          max={@group.door_threat_max}
          unit="threat"
          event="door_delta"
        />
      </div>
    </.panel>
    """
  end

  attr :at, :integer, required: true
  attr :label, :string, required: true

  defp bar_marker(assigns) do
    ~H"""
    <div class="absolute inset-y-0 flex flex-col items-center" style={"left: #{@at}%"}>
      <div class="h-full w-0.5 bg-neutral"></div>
      <span class="absolute -top-0.5 whitespace-nowrap px-1 font-ibm-mono text-[0.55rem] uppercase tracking-[0.1em] text-base-content mix-blend-difference">
        {@label}
      </span>
    </div>
    """
  end

  attr :event, :string, required: true
  attr :id, :string, default: nil
  attr :amount, :string, required: true
  attr :label, :string, required: true
  attr :wide, :boolean, default: false

  defp delta_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@event}
      phx-value-id={@id}
      phx-value-amount={@amount}
      class={[
        "cursor-pointer border-2 border-neutral bg-base-300 font-barlow-condensed font-bold uppercase tracking-[0.06em] text-base-content hover:text-white",
        (@wide && "px-2 py-1 text-[0.7rem]") || "size-8 text-sm flex items-center justify-center"
      ]}
    >
      {@label}
    </button>
    """
  end
end
