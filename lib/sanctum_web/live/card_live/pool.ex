defmodule SanctumWeb.CardLive.Pool do
  @moduledoc """
  Public "Card Pool" — every card side in the game (player *and* encounter) with
  full text and stats, filterable by name, aspect, and type. The comic-dossier
  counterpart to the admin card table.
  """
  use SanctumWeb, :live_view

  require Ash.Query

  import SanctumWeb.Components.CardSideTile
  import SanctumWeb.Components.FilterSheet
  import SanctumWeb.Components.QueryInput

  alias Sanctum.Search.FormSync
  alias SanctumWeb.InfiniteScroll

  @page_size 24

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:cards}>
      <div id="scroll-restore" phx-hook="ScrollRestore" data-offset={@offset}></div>
      <.header>
        Card Pool
      </.header>

      <!-- controls -->
      <div class="mb-6">
        <div class="flex w-full flex-col gap-2 sm:flex-row sm:items-start">
          <form id="card-search" phx-change="search" class="flex w-full sm:min-w-0 sm:flex-1">
            <.query_input
              id="card-query"
              value={@query}
              name="query"
              placeholder="Search cards — try aspect:aggression cost<=2 type:ally"
              placeholder_short="Search cards — try cost<=2"
              registry={Sanctum.Search.CardFields}
              diagnostics={@search_diagnostics}
              help_path={~p"/search-help" <> "#cards"}
            />
          </form>
          <.filter_button
            count={@filter_count}
            class="w-full min-h-[46px] flex-none sm:w-auto sm:min-h-[46px]"
          />
        </div>
        <div class="mt-2 flex items-center gap-2 whitespace-nowrap font-anton text-[15px] uppercase tracking-[0.05em]">
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

      <.filter_sheet
        id="card-filters"
        open?={@filters_open?}
        query={@query}
        registry={Sanctum.Search.CardFields}
        count={@count}
        hide={(@current_user && []) || ["owned"]}
      />

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
      |> assign(:search_diagnostics, [])
      |> assign(:filters_open?, false)
      |> assign(:filter_count, 0)
      # nil until the first async load lands — drives the loading/skeleton UI.
      |> assign(:total, nil)
      |> assign(:count, nil)
      |> assign(:offset, 0)
      |> assign(:end_of_timeline?, false)
      |> assign(:req_id, 0)
      |> assign(:loading?, true)
      |> assign(:scroll_restore_pending?, false)
      |> assign(:hero_colors, %{})
      |> stream(:cards, [])

    {:ok, socket}
  end

  # Filters live in the URL — as the query string itself — so back/forward
  # and shared links restore them. The initial data load also starts here —
  # only on the connected mount (req_id == 0 guards the first pass); the
  # static render just paints the shell.
  @impl true
  def handle_params(params, _uri, socket) do
    query = params["query"] || ""

    case legacy_filter_query(query, params) do
      nil ->
        changed? = query != socket.assigns.query

        socket =
          assign(socket,
            query: query,
            search_diagnostics: search_diagnostics(query),
            filter_count: FormSync.active_count(query, Sanctum.Search.CardFields)
          )

        socket =
          if connected?(socket) and (changed? or socket.assigns.req_id == 0),
            do: reset_and_load(socket),
            else: socket

        {:noreply, socket}

      translated ->
        {:noreply,
         push_patch(socket, to: pool_path(socket.assigns, query: translated), replace: true)}
    end
  end

  # Pre-filter-sheet URLs carried ?aspect= / ?type= params. Fold them into
  # the query string once and re-patch to the canonical URL.
  defp legacy_filter_query(query, params) do
    fields =
      [{"aspect", params["aspect"]}, {"type", params["type"]}]
      |> Enum.filter(fn {name, value} -> legacy_value?(name, value) end)
      |> Map.new(fn {name, value} -> {name, [value]} end)

    if fields == %{},
      do: nil,
      else: FormSync.update(query, Sanctum.Search.CardFields, fields)
  end

  defp legacy_value?(_name, value) when value in [nil, "all"], do: false

  defp legacy_value?(name, value) do
    value in Sanctum.Search.Registry.lookup(Sanctum.Search.CardFields, name).values
  end

  # `replace: true` so typing doesn't spam a history entry per keystroke.
  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, push_patch(socket, to: pool_path(socket.assigns, query: query), replace: true)}
  end

  # Autocomplete for the query input: the QueryInput hook pushes the raw
  # value + cursor and renders whatever we reply with.
  def handle_event("suggest", %{"value" => value, "cursor" => cursor}, socket)
      when is_binary(value) and is_integer(cursor) do
    {:reply, Sanctum.Search.Suggest.suggest(value, cursor, Sanctum.Search.CardFields), socket}
  end

  def handle_event("suggest", _params, socket), do: {:reply, %{items: []}, socket}

  def handle_event("toggle_filters", _params, socket) do
    {:noreply, update(socket, :filters_open?, &(!&1))}
  end

  # A filter-sheet change: splice the submitted controls back into the query
  # string and re-enter the normal search path (URL → handle_params → load),
  # which also pushes the rewritten query into the search input.
  def handle_event("filters_change", params, socket) do
    fields = FormSync.fields_from_params(params, Sanctum.Search.CardFields)
    query = FormSync.update(socket.assigns.query, Sanctum.Search.CardFields, fields)

    {:noreply, push_patch(socket, to: pool_path(socket.assigns, query: query), replace: true)}
  end

  def handle_event("restore-scroll", %{"offset" => offset}, socket) do
    {:noreply, InfiniteScroll.restore_scroll(socket, offset, @page_size, &start_load/3)}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/cards")}
  end

  def handle_event("next-page", _params, socket) do
    {:noreply, InfiniteScroll.next_page(socket, @page_size, &start_load/3)}
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

      {:noreply, InfiniteScroll.maybe_confirm_scroll_restore(socket)}
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

  # A user-initiated reset (filter/search change) cancels any in-flight scroll
  # restore — the saved position belongs to the previous result set.
  defp reset_and_load(socket) do
    socket
    |> assign(:scroll_restore_pending?, false)
    |> start_load(0, reset: true)
  end

  # Kick off the browse read off the socket so the connected mount returns the
  # shell immediately. `hero_colors` is fetched only once per LiveView (it's a
  # static per-set palette map) and reused across every subsequent load.
  #
  # `restore: true` refetches pages 0..offset in one query (for scroll
  # restoration) while keeping `offset` as the logical last-page offset so
  # subsequent viewport loads continue from the right place.
  defp start_load(socket, offset, opts) do
    reset? = Keyword.get(opts, :reset, false)
    restore? = Keyword.get(opts, :restore, false)
    {query_offset, limit} = if restore?, do: {0, offset + @page_size}, else: {offset, @page_size}
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
        |> Ash.read!(page: [limit: limit, offset: query_offset, count: reset?])

      colors = if fetch_colors?, do: Sanctum.Heroes.hero_color_map(), else: nil

      %{req: req, offset: offset, reset?: reset?, page: page, colors: colors}
    end)
  end

  # /cards path carrying the current (or overridden) query, omitted when empty.
  defp pool_path(assigns, overrides) do
    f = Map.merge(filters(assigns), Map.new(overrides))
    params = if f.query == "", do: [], else: [query: f.query]

    ~p"/cards?#{params}"
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
    %{query: assigns.query}
  end

  # Advisory parse/compile problems shown under the query input ("unknown
  # field…", "did you mean…"). The query still runs with the bad part dropped.
  defp search_diagnostics(query) when is_binary(query) and query != "" do
    Sanctum.Search.compile(query, Sanctum.Search.CardFields).diagnostics
  end

  defp search_diagnostics(_query), do: []
end
