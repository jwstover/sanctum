defmodule SanctumWeb.EventLive.Show do
  @moduledoc """
  The Loki Control Center — the live tracking board for a God of Lies event.

  A fullscreen "siege command" surface: a top toolbar, a three-column band
  (time-left rail · Loki, God of Lies HP · Worlds Collide doomsday clock), and a
  per-pod grid of group cards, each with The Mangog and Door Between Worlds
  lifecycle controls. All mutations broadcast over PubSub so multiple organizers
  stay in sync in real time.
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

  # ===========================================================================
  # Render
  # ===========================================================================

  def render(assigns) do
    event = assigns.event
    outcome = outcome(event)

    assigns =
      assigns
      |> assign(:outcome, outcome)
      |> assign(
        :banner_outcome,
        if(outcome == :flipped and assigns.flip_dismissed, do: :none, else: outcome)
      )
      |> assign(:remaining, seconds_remaining(event, assigns.now))
      |> assign(:endgame, worlds_collide_full?(event))
      |> assign(:loki_fill, pct(event.loki_hp || 0, event.loki_hp_max))
      |> assign(:threat_pips, threat_pips(event))

    ~H"""
    <main class="min-h-screen bg-base-100 text-base-content font-barlow-condensed">
      <%!-- Toolbar --%>
      <div class="flex items-center justify-between gap-3 border-b-2 border-neutral bg-neutral/50 px-5 py-3">
        <div class="flex min-w-0 items-center gap-3">
          <.link
            navigate={~p"/events"}
            class="flex size-9 flex-none items-center justify-center border-2 border-neutral bg-base-300 hover:text-white"
            aria-label="Back to events"
          >
            <.icon name="hero-arrow-left" class="size-4" />
          </.link>
          <span class="truncate font-anton text-2xl uppercase leading-none">
            {@event.name}
            <span class="font-barlow-condensed text-sm normal-case text-base-content/40">
              — Loki, God of Lies
            </span>
          </span>
        </div>
        <.link
          navigate={~p"/events/#{@event.id}/setup"}
          class="flex-none border-2 border-neutral bg-base-300 px-3 py-1.5 font-barlow-condensed text-xs font-bold uppercase tracking-[0.1em] hover:text-white"
        >
          Edit roster
        </.link>
      </div>

      <.banner outcome={@banner_outcome} />

      <%!-- Siege band: time · Loki · doomsday --%>
      <div class="grid border-b-2 border-neutral bg-[radial-gradient(90%_70%_at_50%_0%,color-mix(in_oklab,var(--color-error)_14%,var(--color-neutral)),var(--color-neutral)_60%)] lg:grid-cols-[300px_1fr_300px]">
        <%!-- Time-left rail --%>
        <div class="flex flex-col border-b-2 border-neutral p-6 lg:border-b-0 lg:border-r-2">
          <span class="font-ibm-mono text-sm uppercase tracking-[0.24em] text-primary">
            Time left
          </span>
          <div class="mt-3 font-anton text-5xl leading-none text-white">
            {format_clock(@remaining)}
          </div>
          <div class="mt-3 h-2 bg-neutral">
            <div class="h-full bg-primary" style={"width: #{timer_pct(@event, @remaining)}%"}></div>
          </div>
          <span class="mt-2 font-ibm-mono text-xs text-base-content/45">
            of {@event.time_limit_minutes} min
          </span>
          <.confirm_button
            id="confirm-reset-timer"
            message="Restart the countdown from the full time limit?"
            confirm_label="Reset clock"
            phx-click="reset_timer"
            class="mt-4 w-full cursor-pointer border-2 border-neutral bg-base-300 py-2 font-barlow-condensed text-sm font-bold uppercase tracking-[0.08em] hover:text-white"
          >
            Reset clock
          </.confirm_button>
          <div class="mt-auto pt-6">
            <div class="font-bangers text-3xl italic tracking-wide text-primary">SANCTUM</div>
            <span class="font-ibm-mono text-xs tracking-[0.14em] text-base-content/40">
              {@event.total_players || 0} PLAYERS · {@event.total_groups || 0} GROUPS · {@event.total_pods ||
                0} PODS
            </span>
          </div>
        </div>

        <%!-- Loki, God of Lies --%>
        <div class="flex flex-col items-center justify-center px-6 py-10 text-center">
          <span class="font-ibm-mono text-lg uppercase tracking-[0.34em] text-error">
            Loki, God of Lies
          </span>
          <div class="mt-1 flex items-baseline gap-2">
            <span class="font-anton text-8xl leading-[0.72] text-white">{@event.loki_hp || 0}</span>
            <span class="font-anton text-4xl text-base-content/35">/{@event.loki_hp_max || 0}</span>
          </div>
          <span class="mt-2 font-barlow-condensed text-2xl font-black uppercase tracking-[0.05em] text-error">
            {loki_stage_line(@event)}
          </span>

          <%!-- HP bar: counts DOWN; the gold flip line sits at ½ (10×players of 20×players). --%>
          <div class="relative mt-12 h-9 w-4/5 border-2 border-neutral bg-neutral">
            <div class="h-full bg-error transition-all duration-300" style={"width: #{@loki_fill}%"}>
            </div>
            <div class="absolute -bottom-3 -top-3 left-1/2 w-1 -translate-x-1/2 bg-primary"></div>
            <span class="absolute -top-9 left-1/2 -translate-x-1/2 whitespace-nowrap font-barlow-condensed text-sm font-bold uppercase tracking-[0.14em] text-primary">
              ⚑ Flip · ½
            </span>
          </div>

          <div class="mt-9 flex flex-wrap items-center justify-center gap-2">
            <form phx-submit="record_damage" class="flex items-center gap-2">
              <input
                type="text"
                name="amount"
                inputmode="numeric"
                placeholder="dmg"
                autocomplete="off"
                class="w-20 border-2 border-line bg-neutral px-3 py-2.5 text-center font-ibm-mono text-base text-base-content outline-none focus:border-primary"
              />
              <button
                type="submit"
                class="border-2 border-transparent bg-error px-5 py-2.5 font-barlow-condensed text-base font-extrabold uppercase tracking-[0.08em] text-white shadow-comic-sm hover:shadow-comic"
              >
                Deal to Loki
              </button>
            </form>
            <.delta_button event="loki_delta" amount="-1" label="−1" />
            <.delta_button event="loki_delta" amount="1" label="+1" />
            <.confirm_button
              id="confirm-loki-reset"
              message="Reset Loki, God of Lies to full hit points?"
              confirm_label="Reset"
              phx-click="loki_reset"
              class="cursor-pointer border-2 border-neutral bg-base-300 px-3 py-2.5 font-barlow-condensed text-sm font-bold uppercase tracking-[0.06em] text-base-content/70 hover:text-white"
            >
              Reset
            </.confirm_button>
          </div>
        </div>

        <%!-- Worlds Collide doomsday clock --%>
        <div class="flex flex-col border-t-2 border-neutral p-6 lg:border-l-2 lg:border-t-0">
          <span class="font-ibm-mono text-sm uppercase tracking-[0.24em] text-primary">
            Doomsday Clock
          </span>
          <div class="mt-3 flex items-baseline gap-1.5">
            <span class="font-anton text-5xl leading-none text-white">
              {@event.worlds_collide_threat}
            </span>
            <span class="font-anton text-2xl text-base-content/40">
              /{@event.worlds_collide_target || 0}
            </span>
          </div>
          <div class="mt-4 flex min-h-[140px] flex-1 flex-col-reverse gap-1.5">
            <div :for={pip <- @threat_pips} class={["min-h-[10px] flex-1 border", pip_class(pip)]}>
            </div>
          </div>
          <span class="mt-3 font-barlow-condensed text-sm font-bold uppercase tracking-[0.06em] text-primary">
            {@event.worlds_collide_target || 0} = worlds collide · loss
          </span>
          <div class="mt-3 flex gap-2">
            <button
              type="button"
              phx-click="worlds_collide_delta"
              phx-value-amount="-1"
              class="flex-1 border-2 border-neutral bg-base-300 py-2.5 font-barlow-condensed text-sm font-bold uppercase hover:text-white"
            >
              −1
            </button>
            <button
              type="button"
              phx-click="worlds_collide_delta"
              phx-value-amount="1"
              class="flex-[2] border-2 border-transparent bg-primary py-2.5 font-barlow-condensed text-sm font-extrabold uppercase tracking-[0.06em] text-primary-content shadow-comic-sm hover:shadow-comic"
            >
              +1 threat
            </button>
          </div>
        </div>
      </div>

      <%!-- Pod grid --%>
      <div class="grid gap-6 p-6 lg:grid-cols-2">
        <section
          :for={pod <- pods(@event)}
          class="border-2 border-neutral bg-base-100 shadow-comic-sm"
        >
          <div class="flex flex-wrap items-center justify-between gap-2 border-b-2 border-neutral bg-base-300 bg-halftone px-5 py-3">
            <span class="font-anton text-2xl uppercase leading-none">{pod.name}</span>
            <span class="font-ibm-mono text-sm tracking-[0.12em] text-base-content/50">
              {pod_meta(pod)}
            </span>
          </div>

          <p :if={pod.groups == []} class="p-5 font-barlow text-sm text-base-content/50">
            No groups in this pod.
          </p>

          <div class="grid gap-3 p-4 sm:grid-cols-2 xl:grid-cols-3">
            <.group_card :for={group <- pod_groups(pod)} group={group} endgame={@endgame} />
          </div>
        </section>
      </div>
    </main>

    <Layouts.flash_group flash={@flash} />
    """
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  # --- Loki, God of Lies ---
  def handle_event("record_damage", %{"amount" => amount}, socket) do
    case parse_int(amount) do
      {:ok, n} when n != 0 -> adjust_loki(socket, -abs(n))
      _ -> {:noreply, socket}
    end
  end

  def handle_event("loki_delta", %{"amount" => amount}, socket) do
    adjust_loki(socket, String.to_integer(amount))
  end

  def handle_event("loki_reset", _params, socket) do
    # A large positive delta clamps back to full HP and clears the flip.
    adjust_loki(socket, socket.assigns.event.loki_hp_max || 0)
  end

  # --- Worlds Collide ---
  def handle_event("worlds_collide_delta", %{"amount" => amount}, socket) do
    adjust_worlds_collide(socket, String.to_integer(amount))
  end

  # Per-group triggers that each add 1 threat: a group's Mischief and Mayhem
  # completing, and an identity that would be defeated (it flips to alter-ego at
  # 1 HP instead of being removed).
  def handle_event("scheme_completed", _params, socket), do: adjust_worlds_collide(socket, 1)
  def handle_event("identity_defeated", _params, socket), do: adjust_worlds_collide(socket, 1)

  # --- Timer ---
  def handle_event("reset_timer", _params, socket) do
    Events.reset_timer!(socket.assigns.event, actor: actor(socket))
    {:noreply, reload_and_broadcast(socket)}
  end

  # --- Groups: Mangog / Door lifecycle ---
  def handle_event("put_mangog", %{"id" => id}, socket) do
    group = find_group(socket, id)
    # Enters play at full HP (10 × groups in the pod).
    update_group(socket, group, %{mangog_status: :in_play, mangog_hp: group.mangog_hp_max || 0})
  end

  def handle_event("mangog_delta", %{"id" => id, "amount" => amount}, socket) do
    group = find_group(socket, id)
    Events.adjust_mangog_hp!(group, %{amount: String.to_integer(amount)}, actor: actor(socket))
    {:noreply, reload_and_broadcast(socket)}
  end

  def handle_event("defeat_mangog", %{"id" => id}, socket) do
    update_group(socket, find_group(socket, id), %{mangog_status: :defeated})
  end

  def handle_event("put_door", %{"id" => id}, socket) do
    group = find_group(socket, id)
    # Enters play at full threat (7 × groups in the pod), thwarted down toward 0.
    update_group(socket, group, %{door_status: :in_play, door_threat: group.door_threat_max || 0})
  end

  def handle_event("door_delta", %{"id" => id, "amount" => amount}, socket) do
    group = find_group(socket, id)
    Events.adjust_door_threat!(group, %{amount: String.to_integer(amount)}, actor: actor(socket))
    {:noreply, reload_and_broadcast(socket)}
  end

  def handle_event("clear_door", %{"id" => id}, socket) do
    update_group(socket, find_group(socket, id), %{door_status: :cleared})
  end

  # --- Groups: endgame ---
  def handle_event("toggle_phase_ended", %{"id" => id}, socket) do
    group = find_group(socket, id)
    new_status = if group.status == :phases_ended, do: :playing, else: :phases_ended
    update_group(socket, group, %{status: new_status})
  end

  # Dismiss the "Loki has flipped" reminder without changing the flip itself
  # (per-session; it re-arms automatically if Loki is reset and flips again).
  def handle_event("dismiss_flip", _params, socket) do
    {:noreply, assign(socket, :flip_dismissed, true)}
  end

  # --- Live sync + timer tick ---
  def handle_info(:event_updated, socket), do: {:noreply, reload(socket)}
  def handle_info(:tick, socket), do: {:noreply, assign(socket, :now, DateTime.utc_now())}

  # ===========================================================================
  # Mutation helpers
  # ===========================================================================

  defp adjust_loki(socket, amount) do
    Events.adjust_loki_hp!(socket.assigns.event, %{amount: amount}, actor: actor(socket))
    {:noreply, reload_and_broadcast(socket)}
  end

  defp adjust_worlds_collide(socket, amount) do
    Events.adjust_worlds_collide!(socket.assigns.event, %{amount: amount}, actor: actor(socket))
    {:noreply, reload_and_broadcast(socket)}
  end

  defp update_group(socket, group, attrs) do
    Events.update_group!(group, attrs, actor: actor(socket))
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
        # Keep a dismissed flip reminder dismissed, but re-arm it once Loki is
        # no longer flipped so a later re-flip surfaces the banner again.
        dismissed = (socket.assigns[:flip_dismissed] || false) and event.loki_flipped

        socket
        |> assign(:page_title, event.name)
        |> assign(:event, event)
        |> assign(:flip_dismissed, dismissed)

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

  # ===========================================================================
  # Derived view state
  # ===========================================================================

  defp pods(event), do: Enum.sort_by(event.pods, & &1.inserted_at, DateTime)
  defp pod_groups(pod), do: Enum.sort_by(pod.groups, & &1.inserted_at, DateTime)

  defp pod_meta(pod) do
    n = length(pod.groups)
    players = pod.groups |> Enum.map(& &1.player_count) |> Enum.sum()
    mangog = Enum.count(pod.groups, &(&1.mangog_status == :in_play))
    door = Enum.count(pod.groups, &(&1.door_status == :in_play))
    "#{n} grp · #{players}p · mangog #{mangog} · door #{door}"
  end

  defp worlds_collide_full?(event) do
    target = event.worlds_collide_target || 0
    target > 0 and event.worlds_collide_threat >= target
  end

  defp outcome(event) do
    groups = Enum.flat_map(event.pods, & &1.groups)
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

  defp loki_stage_line(event) do
    hp = event.loki_hp || 0
    flip = event.loki_flip_threshold || 0

    cond do
      hp <= 0 -> "Defeated"
      hp > flip -> "Stage I — #{hp - flip} HP to flip"
      true -> "Stage II — #{hp} HP to defeat"
    end
  end

  # Doomsday pips, one per point of the target, filled bottom-up; the top
  # quarter reads as critical.
  defp threat_pips(event) do
    target = event.worlds_collide_target || 0
    threat = event.worlds_collide_threat || 0
    danger_from = if target > 0, do: ceil(target * 0.75), else: 0

    for i <- 0..(target - 1)//1 do
      cond do
        i >= threat -> :off
        i >= danger_from -> :danger
        true -> :on
      end
    end
  end

  defp pip_class(:off), do: "bg-base-300 border-neutral/40"
  defp pip_class(:on), do: "bg-primary border-transparent"
  defp pip_class(:danger), do: "bg-error border-transparent"

  defp seconds_remaining(%{started_at: nil}, _now), do: nil

  defp seconds_remaining(event, now) do
    ends_at = DateTime.add(event.started_at, event.time_limit_minutes * 60, :second)
    max(0, DateTime.diff(ends_at, now, :second))
  end

  defp timer_pct(_event, nil), do: 0
  defp timer_pct(event, remaining), do: pct(remaining, (event.time_limit_minutes || 180) * 60)

  defp format_clock(nil), do: "--:--"

  defp format_clock(total) do
    h = div(total, 3600)
    m = total |> rem(3600) |> div(60)
    s = rem(total, 60)

    if h > 0, do: "#{h}:#{pad(m)}:#{pad(s)}", else: "#{pad(m)}:#{pad(s)}"
  end

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")

  defp pct(_value, 0), do: 0
  defp pct(_value, nil), do: 0
  defp pct(value, max), do: min(100, round(value / max * 100))

  # Mangog / Door tone (color intent) and status text.
  defp mangog_tone(%{mangog_status: :out}), do: :out
  defp mangog_tone(%{mangog_status: :defeated}), do: :resolved

  defp mangog_tone(%{mangog_status: :in_play, mangog_hp: hp, mangog_hp_max: max}),
    do: if(max && max > 0 && hp <= max * 0.2, do: :danger, else: :active)

  defp door_tone(%{door_status: :out}), do: :out
  defp door_tone(%{door_status: :cleared}), do: :resolved

  defp door_tone(%{door_status: :in_play, door_threat: t, door_threat_max: max}),
    do: if(max && max > 0 && t >= max * 0.7, do: :danger, else: :active)

  defp mangog_status_text(:out), do: "Out of play"
  defp mangog_status_text(:in_play), do: "In play"
  defp mangog_status_text(:defeated), do: "Defeated"

  defp door_status_text(:out), do: "Out of play"
  defp door_status_text(:in_play), do: "In play"
  defp door_status_text(:cleared), do: "Cleared"

  defp tone_value(:out), do: "text-base-content/40"
  defp tone_value(:active), do: "text-primary"
  defp tone_value(:danger), do: "text-error"
  defp tone_value(:resolved), do: "text-secondary"

  defp tone_badge(:out), do: "border-base-content/30 text-base-content/50"
  defp tone_badge(:active), do: "border-primary text-primary"
  defp tone_badge(:danger), do: "border-error text-error"
  defp tone_badge(:resolved), do: "border-secondary text-secondary"

  # ===========================================================================
  # View components
  # ===========================================================================

  attr :outcome, :atom, required: true

  defp banner(%{outcome: :none} = assigns), do: ~H""

  defp banner(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-3 border-b-2 border-neutral px-5 py-3",
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
      <button
        :if={@outcome == :flipped}
        type="button"
        phx-click="dismiss_flip"
        class="ml-auto flex flex-none items-center gap-1.5 border-2 border-primary px-2.5 py-1 font-barlow-condensed text-xs font-bold uppercase tracking-[0.08em] text-primary hover:bg-primary hover:text-primary-content"
      >
        <.icon name="hero-x-mark" class="size-3.5" /> Clear
      </button>
    </div>
    """
  end

  defp banner_text(:won), do: "Loki, God of Lies is defeated — all players win!"
  defp banner_text(:lost), do: "Worlds Collide is complete and all phases ended — players lose."

  defp banner_text(:verge),
    do: "Worlds Collide has reached its target — players are on the verge of losing!"

  defp banner_text(:flipped),
    do: "Loki has flipped — pause all groups and apply Intense / Total Focus."

  attr :group, :map, required: true
  attr :endgame, :boolean, required: true

  defp group_card(assigns) do
    ~H"""
    <div class={[
      "flex flex-col gap-3 border-2 border-neutral bg-base-200 p-4",
      @group.status == :phases_ended && "border-warning"
    ]}>
      <div class="flex items-baseline justify-between gap-2">
        <span class="min-w-0 truncate font-barlow-condensed text-xl font-bold uppercase tracking-[0.04em]">
          {@group.name}
        </span>
        <span class="flex-none font-ibm-mono text-xs uppercase tracking-[0.1em] text-base-content/40">
          {difficulty_abbr(@group.difficulty)} · {@group.player_count}p
        </span>
      </div>

      <.lifecycle_row
        id={@group.id}
        label="The Mangog"
        status_text={mangog_status_text(@group.mangog_status)}
        resolved={@group.mangog_status == :defeated}
        out={@group.mangog_status == :out}
        in_play={@group.mangog_status == :in_play}
        tone={mangog_tone(@group)}
        value={@group.mangog_hp}
        max={@group.mangog_hp_max}
        unit={"/#{@group.mangog_hp_max} HP"}
        put_event="put_mangog"
        put_label={"+ Put into play · #{@group.mangog_hp_max} HP"}
        delta_event="mangog_delta"
        resolve_event="defeat_mangog"
        resolve_label="Defeated"
      />

      <.lifecycle_row
        id={@group.id}
        label="Door Between Worlds"
        status_text={door_status_text(@group.door_status)}
        resolved={@group.door_status == :cleared}
        out={@group.door_status == :out}
        in_play={@group.door_status == :in_play}
        tone={door_tone(@group)}
        value={@group.door_threat}
        max={@group.door_threat_max}
        unit=" thr"
        put_event="put_door"
        put_label={"+ Put into play · #{@group.door_threat_max} threat"}
        delta_event="door_delta"
        resolve_event="clear_door"
        resolve_label="Cleared"
      />

      <%!-- Per-group Worlds Collide triggers (each +1 threat). --%>
      <div class="mt-1 grid grid-cols-2 gap-2 border-t-2 border-neutral/30 pt-3">
        <button
          type="button"
          phx-click="scheme_completed"
          class="border-2 border-neutral bg-base-300 px-2 py-1.5 font-barlow-condensed text-[0.7rem] font-bold uppercase leading-tight tracking-[0.04em] hover:text-white"
        >
          M&amp;M done <span class="text-base-content/50">+1 WC</span>
        </button>
        <button
          type="button"
          phx-click="identity_defeated"
          class="border-2 border-neutral bg-base-300 px-2 py-1.5 font-barlow-condensed text-[0.7rem] font-bold uppercase leading-tight tracking-[0.04em] hover:text-white"
        >
          Identity down <span class="text-base-content/50">+1 WC</span>
        </button>
      </div>

      <%!-- Endgame only: mark this group's final player phase ended. --%>
      <button
        :if={@endgame}
        type="button"
        phx-click="toggle_phase_ended"
        phx-value-id={@group.id}
        class={[
          "w-full border-2 border-neutral px-2 py-1.5 font-barlow-condensed text-[0.7rem] font-bold uppercase tracking-[0.06em]",
          (@group.status == :phases_ended && "bg-warning text-neutral") ||
            "bg-base-300 hover:text-white"
        ]}
      >
        {if @group.status == :phases_ended, do: "✓ Final phase ended", else: "Mark final phase ended"}
      </button>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :status_text, :string, required: true
  attr :out, :boolean, required: true
  attr :in_play, :boolean, required: true
  attr :resolved, :boolean, required: true
  attr :tone, :atom, required: true
  attr :value, :integer, required: true
  attr :max, :integer, required: true
  attr :unit, :string, required: true
  attr :put_event, :string, required: true
  attr :put_label, :string, required: true
  attr :delta_event, :string, required: true
  attr :resolve_event, :string, required: true
  attr :resolve_label, :string, required: true

  defp lifecycle_row(assigns) do
    ~H"""
    <div class="flex flex-col gap-2">
      <div class="flex items-center justify-between gap-2">
        <span class="font-barlow-condensed text-base font-bold">{@label}</span>
        <span class={[
          "border px-1.5 py-0.5 font-ibm-mono text-[0.62rem] uppercase tracking-[0.08em]",
          tone_badge(@tone)
        ]}>
          {@status_text}
        </span>
      </div>

      <button
        :if={@out}
        type="button"
        phx-click={@put_event}
        phx-value-id={@id}
        class="border-2 border-neutral bg-base-300 px-2 py-2.5 font-barlow-condensed text-[0.8rem] font-bold uppercase tracking-[0.05em] hover:text-white"
      >
        {@put_label}
      </button>

      <div :if={@in_play} class="flex items-center gap-1.5">
        <.delta_button event={@delta_event} id={@id} amount="-1" label="−1" />
        <span class={["flex-1 text-center font-anton text-xl leading-none", tone_value(@tone)]}>
          {@value}<span class="font-barlow-condensed text-xs text-base-content/40">{@unit}</span>
        </span>
        <.delta_button event={@delta_event} id={@id} amount="1" label="+1" />
        <button
          type="button"
          phx-click={@resolve_event}
          phx-value-id={@id}
          class="border-2 border-secondary bg-secondary/15 px-2.5 py-1.5 font-barlow-condensed text-[0.7rem] font-bold uppercase tracking-[0.05em] text-secondary hover:bg-secondary/25"
        >
          {@resolve_label}
        </button>
      </div>
    </div>
    """
  end

  attr :event, :string, required: true
  attr :id, :string, default: nil
  attr :amount, :string, required: true
  attr :label, :string, required: true

  defp delta_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@event}
      phx-value-id={@id}
      phx-value-amount={@amount}
      class="flex size-9 flex-none items-center justify-center border-2 border-neutral bg-base-300 font-barlow-condensed text-sm font-bold text-base-content hover:text-white"
    >
      {@label}
    </button>
    """
  end

  defp difficulty_abbr(:standard), do: "STD"
  defp difficulty_abbr(:expert), do: "EXP"
end
