defmodule SanctumWeb.CardLive.Pool do
  @moduledoc """
  Public "Card Pool" — every card side in the game (player *and* encounter) with
  full text and stats, filterable by name, aspect, and type. The comic-dossier
  counterpart to the admin card table.
  """
  use SanctumWeb, :live_view

  require Ash.Query

  import SanctumWeb.Components.CardSideTile

  @page_size 24

  @aspects [
    {"all", "All", nil},
    {"hero", "Hero", "bg-aspect-hero"},
    {"aggression", "Aggression", "bg-aspect-aggression"},
    {"justice", "Justice", "bg-aspect-justice"},
    {"leadership", "Leadership", "bg-aspect-leadership"},
    {"protection", "Protection", "bg-aspect-protection"},
    {"pool", "Pool", "bg-aspect-pool"},
    {"basic", "Basic", "bg-aspect-basic"}
  ]

  @types [
    {"all", "All"},
    {"ally", "Ally"},
    {"event", "Event"},
    {"support", "Support"},
    {"upgrade", "Upgrade"},
    {"resource", "Resource"},
    {"player_side_scheme", "Side Scheme"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:cards}>
      <.header>
        Card Pool
        <:subtitle>
          Every card in the game — player and encounter — with full text and stats. Filter by aspect or type to find what you need.
        </:subtitle>
      </.header>

      <!-- controls -->
      <div class="mb-3.5 flex flex-wrap items-center gap-2.5">
        <form id="card-search" phx-change="search" class="relative min-w-[260px] flex-1">
          <span class="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-[17px] text-base-content/40">
            ⌕
          </span>
          <input
            type="text"
            name="query"
            value={@query}
            phx-debounce="200"
            autocomplete="off"
            placeholder="Search cards by name…"
            class="w-full border-[2.5px] border-line bg-black px-3.5 py-2.5 pl-[38px] font-barlow text-base text-base-content outline-none focus:border-primary sm:text-[15px]"
          />
        </form>
        <div class="flex items-center gap-2 whitespace-nowrap font-anton text-[15px] uppercase tracking-[0.05em]">
          <.icon
            :if={@loading?}
            name="hero-arrow-path"
            class="size-4 animate-spin text-base-content/45"
          />
          <span :if={@count == nil} class="text-base-content/45">Loading…</span>
          <span :if={@count != nil}>
            {@count} <span class="text-base-content/45">/ {@total} cards</span>
          </span>
        </div>
      </div>

      <!-- aspect filters -->
      <div class="mb-2.5 flex flex-wrap gap-1.5">
        <.filter_pill
          :for={{key, label, dot_class} <- @aspect_options}
          active={@aspect == key}
          dot_class={dot_class}
          phx-click="filter_aspect"
          phx-value-key={key}
        >
          {label}
        </.filter_pill>
      </div>

      <!-- type filters -->
      <div class="mb-6 flex flex-wrap gap-1.5">
        <.filter_pill
          :for={{key, label} <- @type_options}
          active={@type == key}
          phx-click="filter_type"
          phx-value-key={key}
        >
          {label}
        </.filter_pill>
      </div>

      <!-- first-load skeletons: shown until the async load delivers a count -->
      <div
        :if={@count == nil}
        class="grid grid-cols-1 items-start gap-[18px] sm:grid-cols-[repeat(auto-fill,minmax(452px,1fr))]"
      >
        <.card_skeleton :for={_ <- 1..6} />
      </div>

      <!-- dossier grid -->
      <div
        id="card-pool"
        phx-update="stream"
        phx-viewport-bottom={!@end_of_timeline? && "next-page"}
        class={[
          "grid grid-cols-1 items-start gap-[18px] sm:grid-cols-[repeat(auto-fill,minmax(452px,1fr))]",
          @loading? && @count != nil && "opacity-60 transition-opacity"
        ]}
      >
        <.card_side_tile
          :for={{dom_id, side} <- @streams.cards}
          id={dom_id}
          side={side}
          navigate={~p"/cards/#{side.card_id}"}
        />
      </div>

      <!-- empty state -->
      <.panel
        :if={@count == 0}
        class="mt-2 border-dashed !border-[#2a2a30] px-6 py-12 text-center !shadow-none"
      >
        <div class="font-bangers text-[30px] tracking-[0.02em] text-primary">No cards found</div>
        <div class="mt-1.5 font-barlow text-[14px] text-base-content/55">
          Try a different search or clear your filters.
        </div>
        <.button variant="primary" phx-click="clear" class="mt-4">Clear filters</.button>
      </.panel>
    </Layouts.app>
    """
  end

  # Placeholder tile matching the card grid's footprint, shown while the first
  # page loads so the layout doesn't jump when real tiles stream in.
  defp card_skeleton(assigns) do
    ~H"""
    <div class="flex animate-pulse gap-[13px] border-2 border-neutral bg-base-200 p-2 shadow-comic">
      <div class="h-[180px] w-[128px] flex-none border-2 border-neutral bg-base-300"></div>
      <div class="flex min-w-0 flex-1 flex-col gap-2 py-1">
        <div class="h-2 w-1/3 bg-base-300"></div>
        <div class="h-5 w-2/3 bg-base-300"></div>
        <div class="mt-2 h-3 w-full bg-base-300"></div>
        <div class="h-3 w-5/6 bg-base-300"></div>
        <div class="h-3 w-4/6 bg-base-300"></div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Card Pool")
      |> assign(:query, "")
      |> assign(:aspect, "all")
      |> assign(:type, "all")
      # nil until the first async load lands — drives the loading/skeleton UI.
      |> assign(:total, nil)
      |> assign(:count, nil)
      |> assign(:aspect_options, @aspects)
      |> assign(:type_options, @types)
      |> assign(:offset, 0)
      |> assign(:end_of_timeline?, false)
      |> assign(:req_id, 0)
      |> assign(:loading?, true)
      |> assign(:hero_colors, %{})
      |> stream(:cards, [])

    # Skip every query on the static (disconnected) render — it exists only to
    # paint the shell fast. The real data loads asynchronously once the socket
    # connects, so nothing blocks time-to-first-paint.
    socket = if connected?(socket), do: start_load(socket, 0, reset: true), else: socket

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, socket |> assign(:query, query) |> reset_and_load()}
  end

  def handle_event("filter_aspect", %{"key" => key}, socket) do
    {:noreply, socket |> assign(:aspect, key) |> reset_and_load()}
  end

  def handle_event("filter_type", %{"key" => key}, socket) do
    {:noreply, socket |> assign(:type, key) |> reset_and_load()}
  end

  def handle_event("clear", _params, socket) do
    {:noreply,
     socket
     |> assign(query: "", aspect: "all", type: "all")
     |> reset_and_load()}
  end

  # Ignore the viewport trigger while a page is already in flight so a burst of
  # scroll events can't fan out into overlapping loads.
  def handle_event("next-page", _params, socket) do
    if socket.assigns.end_of_timeline? or socket.assigns.loading? do
      {:noreply, socket}
    else
      {:noreply, start_load(socket, socket.assigns.offset + @page_size)}
    end
  end

  @impl true
  def handle_async(:load_cards, {:ok, result}, socket) do
    %{req: req, offset: offset, reset?: reset?, page: page, colors: colors} = result

    # A newer filter/search/page request has since fired; drop these stale
    # results so out-of-order completions can't clobber the current view.
    if req == socket.assigns.req_id do
      hero_colors = colors || socket.assigns.hero_colors

      socket =
        socket
        |> assign(:hero_colors, hero_colors)
        |> assign(:offset, offset)
        |> assign(:end_of_timeline?, !page.more?)
        |> assign(:loading?, false)
        |> maybe_assign_count(reset?, page.count)
        |> stream(
          :cards,
          Enum.map(page.results, &side_view(&1, hero_colors)),
          reset: reset?
        )

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:load_cards, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:loading?, false)
     |> put_flash(:error, "Couldn’t load cards: #{inspect(reason)}")}
  end

  defp reset_and_load(socket), do: start_load(socket, 0, reset: true)

  # Kick off the browse read off the socket so the connected mount returns the
  # shell immediately. `hero_colors` is fetched only once per LiveView (it's a
  # static per-set palette map) and reused across every subsequent load.
  defp start_load(socket, offset, opts \\ []) do
    reset? = Keyword.get(opts, :reset, false)
    req = socket.assigns.req_id + 1
    filters = filters(socket.assigns)
    actor = socket.assigns[:current_user]
    fetch_colors? = socket.assigns.hero_colors == %{}

    socket
    |> assign(:req_id, req)
    |> assign(:loading?, true)
    |> start_async(:load_cards, fn ->
      page =
        Sanctum.Games.CardSide
        |> Ash.Query.for_read(:browse, filters, actor: actor)
        |> Ash.read!(page: [limit: @page_size, offset: offset, count: reset?])

      colors = if fetch_colors?, do: Sanctum.Heroes.hero_color_map(), else: nil

      %{req: req, offset: offset, reset?: reset?, page: page, colors: colors}
    end)
  end

  # `page.count` is only queried on reset loads (count: reset?). `total` is the
  # full unfiltered catalog size — set once from the first load (mount always
  # runs unfiltered) and left untouched as filters narrow the visible count.
  defp maybe_assign_count(socket, false, _count), do: socket

  defp maybe_assign_count(socket, true, count) do
    socket
    |> assign(:count, count)
    |> then(fn s -> if is_nil(s.assigns.total), do: assign(s, :total, count), else: s end)
  end

  defp filters(assigns) do
    %{query: assigns.query, aspect: assigns.aspect, type: assigns.type}
  end
end
