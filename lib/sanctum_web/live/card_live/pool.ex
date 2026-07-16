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
        <form phx-change="search" class="relative min-w-[260px] flex-1">
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
        <div class="whitespace-nowrap font-anton text-[15px] uppercase tracking-[0.05em]">
          {@count} <span class="text-base-content/45">/ {@total} cards</span>
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

      <!-- dossier grid -->
      <div
        id="card-pool"
        phx-update="stream"
        phx-viewport-bottom={!@end_of_timeline? && "next-page"}
        class="grid grid-cols-1 items-start gap-[18px] sm:grid-cols-[repeat(auto-fill,minmax(452px,1fr))]"
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

  @impl true
  def mount(_params, _session, socket) do
    total = count_cards(socket, %{})

    {:ok,
     socket
     |> assign(:page_title, "Card Pool")
     |> assign(:query, "")
     |> assign(:aspect, "all")
     |> assign(:type, "all")
     |> assign(:total, total)
     |> assign(:count, total)
     |> assign(:aspect_options, @aspects)
     |> assign(:type_options, @types)
     |> assign(:offset, 0)
     |> assign(:end_of_timeline?, false)
     |> assign(:hero_colors, Sanctum.Heroes.hero_color_map())
     |> stream(:cards, [])
     |> load_page(0, reset: true)}
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

  def handle_event("next-page", _params, socket) do
    if socket.assigns.end_of_timeline? do
      {:noreply, socket}
    else
      {:noreply, load_page(socket, socket.assigns.offset + @page_size)}
    end
  end

  defp reset_and_load(socket), do: load_page(socket, 0, reset: true)

  defp load_page(socket, offset, opts \\ []) do
    reset? = Keyword.get(opts, :reset, false)

    page =
      Sanctum.Games.CardSide
      |> Ash.Query.for_read(:browse, filters(socket.assigns),
        actor: socket.assigns[:current_user]
      )
      |> Ash.read!(page: [limit: @page_size, offset: offset, count: reset?])

    socket
    |> assign(:offset, offset)
    |> assign(:end_of_timeline?, !page.more?)
    |> then(fn s -> if reset?, do: assign(s, :count, page.count), else: s end)
    |> stream(
      :cards,
      Enum.map(page.results, &side_view(&1, socket.assigns.hero_colors)),
      reset: reset?
    )
  end

  defp count_cards(socket, extra_filters) do
    Sanctum.Games.CardSide
    |> Ash.Query.for_read(:browse, Map.merge(%{aspect: "all", type: "all"}, extra_filters),
      actor: socket.assigns[:current_user]
    )
    |> Ash.read!(page: [limit: 1, offset: 0, count: true])
    |> Map.get(:count)
  end

  defp filters(assigns) do
    %{query: assigns.query, aspect: assigns.aspect, type: assigns.type}
  end
end
