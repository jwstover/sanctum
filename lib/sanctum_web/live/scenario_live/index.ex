defmodule SanctumWeb.ScenarioLive.Index do
  @moduledoc """
  Public "Browse Scenarios" — a feed of official and user-built scenarios
  filterable with the scenario query language, with Newest / A–Z sorting.
  The scenario counterpart of the deck browser.
  """
  use SanctumWeb, :live_view

  import SanctumWeb.Components.FilterSheet
  import SanctumWeb.Components.QueryInput
  import SanctumWeb.Components.ScenarioCards

  alias Sanctum.Search.FormSync
  alias SanctumWeb.InfiniteScroll
  alias SanctumWeb.Timezone

  @page_size 24

  # :browse already loads owner, villain_set and modular_set_count.
  @extra_loads [villains: [:primary_side]]

  @sorts [{"new", "Newest"}, {"name", "A–Z"}]
  @sort_keys Enum.map(@sorts, &elem(&1, 0))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:scenarios}>
      <div id="scroll-restore" phx-hook="ScrollRestore" data-offset={@offset}></div>
      <.header>
        Browse Scenarios
        <:actions>
          <.button :if={@current_user} variant="primary" navigate={~p"/scenarios/new"}>
            <.icon name="hero-plus" /> New Scenario
          </.button>
        </:actions>
      </.header>

      <!-- search + count -->
      <div class="mb-6">
        <div class="flex w-full flex-col gap-2 sm:flex-row sm:items-start">
          <form id="scenario-search" phx-change="search" class="flex w-full sm:min-w-0 sm:flex-1">
            <.query_input
              id="scenario-query"
              value={@query}
              name="query"
              placeholder={~s(Search scenarios — try villain:rhino set:"bomb scare" is:official)}
              placeholder_short="Search scenarios — try villain:rhino"
              registry={Sanctum.Search.ScenarioFields}
              diagnostics={@search_diagnostics}
              help_path={~p"/search-help" <> "#scenarios"}
            />
          </form>
          <.filter_button
            count={@filter_count}
            class="w-full min-h-[46px] flex-none sm:w-auto sm:min-h-[46px]"
          />
        </div>
        <div class="mt-2 flex items-center gap-2 whitespace-nowrap font-anton text-base uppercase tracking-[0.05em]">
          <.icon
            :if={@loading?}
            name="hero-arrow-path"
            class="size-4 animate-spin text-base-content/45"
          />
          <span :if={@count == nil} class="text-base-content/45">Loading…</span>
          <span :if={@count != nil}>
            {@count} <span class="text-base-content/45">/ {@total} scenarios</span>
          </span>
        </div>
      </div>

      <.filter_sheet
        id="scenario-filters"
        open?={@filters_open?}
        query={@query}
        registry={Sanctum.Search.ScenarioFields}
        count={@count}
        hide={(@current_user && []) || ["is:mine"]}
      >
        <:body_extra>
          <h3 class="mb-2.5 font-anton text-sm uppercase tracking-[0.08em] text-base-content/45">
            Sort
          </h3>
          <div class="flex flex-wrap gap-1.5" role="radiogroup" aria-label="Sort scenarios">
            <.chip
              :for={{key, label} <- @sort_options}
              type="radio"
              name="sort"
              value={key}
              checked={@sort == key}
            >
              {label}
            </.chip>
          </div>
        </:body_extra>
      </.filter_sheet>

      <!-- first-load skeletons: shown until the async load delivers a count -->
      <.deck_tile_skeleton_grid :if={@count == nil} />

      <!-- feed -->
      <div
        id="scenario-feed"
        phx-update="stream"
        phx-viewport-bottom={!@end_of_timeline? && "next-page"}
        class={[
          "grid grid-cols-1 items-start gap-3 sm:grid-cols-[repeat(auto-fill,minmax(520px,1fr))]",
          @loading? && @count != nil && "opacity-60 transition-opacity"
        ]}
      >
        <div
          :for={{dom_id, s} <- @streams.scenarios}
          id={dom_id}
          class="mc-tile relative flex items-stretch gap-3 border-2 border-neutral bg-base-200 p-3 shadow-comic sm:gap-4 sm:p-3.5"
        >
          <!-- Stretched-link pattern: the whole tile navigates via this overlay anchor. -->
          <.link
            navigate={~p"/scenarios/#{s.id}"}
            aria-label={s.name}
            class="absolute inset-0 z-[1]"
          >
            <span class="sr-only">{s.name}</span>
          </.link>
          <div class="h-[151px] w-[108px] flex-none border-2 border-neutral shadow-comic-sm">
            <.mc_card
              name={s.villain_name || s.name}
              aspect="encounter"
              image_url={s.villain_image}
              size="md"
              show_cost={false}
            />
          </div>

          <div class="flex min-w-0 flex-1 flex-col">
            <div
              :if={s.villain_set_name}
              class="font-ibm-mono text-xs uppercase tracking-[0.08em] text-primary"
            >
              {s.villain_set_name}
            </div>
            <div class="mt-1 break-words font-anton text-2xl uppercase leading-[0.95]">
              {s.name}
            </div>
            <div class="mt-1.5 font-barlow-condensed text-sm font-bold uppercase tracking-[0.1em] text-base-content/60">
              {modular_label(s.modular_set_count)}
            </div>
            <div :if={s.author} class="mt-auto flex items-center gap-2 pt-3">
              <.official_badge :if={s.author.official?} />
              <%= if !s.author.official? do %>
                <.avatar name={s.author.name} url={s.author.avatar} />
                <span class="font-barlow-condensed text-sm font-bold text-primary">
                  {s.author.name}
                </span>
              <% end %>
              <span class="ml-auto font-ibm-mono text-xs text-base-content/40">{s.updated}</span>
            </div>
            <div :if={!s.author} class="mt-auto pt-3 font-ibm-mono text-xs text-base-content/40">
              {s.updated}
            </div>
          </div>
        </div>
      </div>

      <!-- empty state -->
      <.panel
        :if={@count == 0}
        class="mt-2 border-dashed !border-[#2a2a30] px-6 py-12 text-center !shadow-none"
      >
        <%= if @total == 0 do %>
          <div class="font-bangers text-3xl tracking-[0.02em] text-primary">No scenarios yet</div>
          <div class="mt-1.5 font-barlow text-sm text-base-content/55">
            Official scenarios will appear here once they're added.
          </div>
        <% else %>
          <div class="font-bangers text-3xl tracking-[0.02em] text-primary">No scenarios found</div>
          <div class="mt-1.5 font-barlow text-sm text-base-content/55">
            Try a different search or clear your filters.
          </div>
          <.button variant="primary" phx-click="clear" class="mt-4">Clear filters</.button>
        <% end %>
      </.panel>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> InfiniteScroll.init_browse("Browse Scenarios", @sorts)
      |> stream(:scenarios, [])

    {:ok, socket}
  end

  # Filters live in the URL (the query string plus a sidecar `sort`), so
  # back/forward and shared links restore them. The data load starts here,
  # only on the connected mount.
  @impl true
  def handle_params(params, _uri, socket) do
    query = params["query"] || ""
    sort = if params["sort"] in @sort_keys, do: params["sort"], else: "new"
    changed? = query != socket.assigns.query or sort != socket.assigns.sort

    socket =
      assign(socket,
        query: query,
        sort: sort,
        search_diagnostics: search_diagnostics(query),
        filter_count: FormSync.active_count(query, Sanctum.Search.ScenarioFields)
      )

    socket =
      if connected?(socket) and (changed? or socket.assigns.req_id == 0),
        do: reset_and_load(socket),
        else: socket

    {:noreply, socket}
  end

  # `replace: true` so typing doesn't spam a history entry per keystroke.
  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply,
     push_patch(socket, to: scenarios_path(socket.assigns, query: query), replace: true)}
  end

  def handle_event("suggest", %{"value" => value, "cursor" => cursor}, socket)
      when is_binary(value) and is_integer(cursor) do
    {:reply, Sanctum.Search.Suggest.suggest(value, cursor, Sanctum.Search.ScenarioFields), socket}
  end

  def handle_event("suggest", _params, socket), do: {:reply, %{items: []}, socket}

  def handle_event("toggle_filters", _params, socket) do
    {:noreply, update(socket, :filters_open?, &(!&1))}
  end

  def handle_event("filters_change", params, socket) do
    {query, sort} =
      InfiniteScroll.sheet_change(
        params,
        socket.assigns.query,
        Sanctum.Search.ScenarioFields,
        @sort_keys,
        socket.assigns.sort
      )

    {:noreply,
     push_patch(socket,
       to: scenarios_path(socket.assigns, query: query, sort: sort),
       replace: true
     )}
  end

  def handle_event("restore-scroll", %{"offset" => offset}, socket) do
    {:noreply, InfiniteScroll.restore_scroll(socket, offset, @page_size, &start_load/3)}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/scenarios")}
  end

  def handle_event("next-page", _params, socket) do
    {:noreply, InfiniteScroll.next_page(socket, @page_size, &start_load/3)}
  end

  @impl true
  def handle_async(:load_scenarios, {:ok, result}, socket) do
    {:noreply,
     InfiniteScroll.put_page(
       socket,
       :scenarios,
       result,
       &scenario_view(&1, socket.assigns.timezone)
     )}
  end

  def handle_async(:load_scenarios, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:loading?, false)
     |> put_flash(:error, "Couldn’t load scenarios: #{inspect(reason)}")}
  end

  # A user-initiated reset cancels any in-flight scroll restore — the saved
  # position belongs to the previous result set.
  defp reset_and_load(socket) do
    socket
    |> assign(:scroll_restore_pending?, false)
    |> start_load(0, reset: true)
  end

  defp start_load(socket, offset, opts) do
    {_, _, reset?} = window = InfiniteScroll.load_opts(offset, @page_size, opts)
    req = socket.assigns.req_id + 1
    args = %{query: socket.assigns.query, sort: socket.assigns.sort}
    actor = socket.assigns[:current_user]
    # The unfiltered total is fetched independently so it stays accurate when
    # the page first loads with filters already in the URL.
    fetch_total? = is_nil(socket.assigns.total)

    socket
    |> assign(:req_id, req)
    |> assign(:loading?, true)
    |> start_async(:load_scenarios, fn ->
      page =
        InfiniteScroll.read_page(Sanctum.Games.Scenario, args, actor, window, @extra_loads)

      total =
        if fetch_total?, do: InfiniteScroll.count_all(Sanctum.Games.Scenario, actor), else: nil

      %{req: req, offset: offset, reset?: reset?, page: page, total: total}
    end)
  end

  # /scenarios path carrying the current (or overridden) filters, omitting defaults.
  defp scenarios_path(assigns, overrides) do
    f = Map.merge(%{query: assigns.query, sort: assigns.sort}, Map.new(overrides))
    ~p"/scenarios?#{InfiniteScroll.browse_params(f.query, f.sort, "new")}"
  end

  # Advisory parse/compile problems shown under the query input.
  defp search_diagnostics(query) when is_binary(query) and query != "" do
    Sanctum.Search.compile(query, Sanctum.Search.ScenarioFields).diagnostics
  end

  defp search_diagnostics(_query), do: []

  defp scenario_view(s, timezone) do
    %{
      id: s.id,
      name: s.name,
      villain_name: villain_name(s),
      villain_set_name: s.villain_set && s.villain_set.name,
      villain_image: villain_image(s),
      modular_set_count: s.modular_set_count || 0,
      author: author(s),
      updated: format_date(s.updated_at, timezone)
    }
  end

  defp modular_label(0), do: "No modular sets"
  defp modular_label(1), do: "1 modular set"
  defp modular_label(n), do: "#{n} modular sets"

  defp format_date(%DateTime{} = dt, timezone),
    do: dt |> Timezone.to_local(timezone) |> Calendar.strftime("%b %-d, %Y")

  defp format_date(_value, _timezone), do: ""
end
