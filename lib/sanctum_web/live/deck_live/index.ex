defmodule SanctumWeb.DeckLive.Index do
  @moduledoc """
  Public "Deck Browser" — a feed of decks filterable by name/hero, aspect, and
  hero, with Newest / A–Z sorting. The comic-dossier counterpart to the admin
  deck table.
  """
  use SanctumWeb, :live_view

  require Ash.Query

  import SanctumWeb.Components.FilterSheet
  import SanctumWeb.Components.QueryInput

  alias Sanctum.Search.FormSync
  alias SanctumWeb.Components.DeckCards
  alias SanctumWeb.InfiniteScroll
  alias SanctumWeb.Timezone

  @page_size 24

  @sorts [{"new", "Newest"}, {"unique", "Unique"}, {"title", "A–Z"}]
  @sort_keys Enum.map(@sorts, &elem(&1, 0))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:decks}>
      <div id="scroll-restore" phx-hook="ScrollRestore" data-offset={@offset}></div>
      <.header>
        Browse Decks
        <:subtitle>
          Every deck in the vault. Filter by hero or aspect, then open one for the full list.
        </:subtitle>
        <:actions>
          <.button :if={@current_user} variant="primary" navigate={~p"/decks/new"}>
            <.icon name="hero-plus" /> New Deck
          </.button>
        </:actions>
      </.header>

      <!-- search + count -->
      <div class="mb-6">
        <div class="flex w-full items-start gap-2">
          <form id="deck-search" phx-change="search" class="flex min-w-0 flex-1">
            <.query_input
              id="deck-query"
              value={@query}
              name="query"
              placeholder="Search decks — try hero:spider aspect:justice cards>=45"
              placeholder_short="Search decks — try hero:spider"
              registry={Sanctum.Search.DeckFields}
              diagnostics={@search_diagnostics}
              help_path={~p"/search-help" <> "#decks"}
            />
          </form>
          <.filter_button count={@filter_count} class="min-h-[46px] flex-none sm:min-h-[46px]" />
        </div>
        <div class="mt-2 flex items-center gap-2 whitespace-nowrap font-anton text-[15px] uppercase tracking-[0.05em]">
          <.icon
            :if={@loading?}
            name="hero-arrow-path"
            class="size-4 animate-spin text-base-content/45"
          />
          <span :if={@count == nil} class="text-base-content/45">Loading…</span>
          <span :if={@count != nil}>
            {@count} <span class="text-base-content/45">/ {@total} decks</span>
          </span>
        </div>
      </div>

      <.filter_sheet
        id="deck-filters"
        open?={@filters_open?}
        query={@query}
        registry={Sanctum.Search.DeckFields}
        count={@count}
        hide={(@current_user && []) || ["mine"]}
      >
        <:footer_extra>
          <div
            class="flex items-center gap-1.5"
            role="radiogroup"
            aria-label="Sort decks"
          >
            <span class="font-barlow-condensed text-[13px] font-bold uppercase tracking-[0.07em] text-base-content/70">
              Sort
            </span>
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
        </:footer_extra>
      </.filter_sheet>

      <!-- first-load skeletons: shown until the async load delivers a count -->
      <.deck_tile_skeleton_grid :if={@count == nil} />

      <!-- feed -->
      <div
        id="deck-feed"
        phx-update="stream"
        phx-viewport-bottom={!@end_of_timeline? && "next-page"}
        class={[
          "grid grid-cols-1 items-start gap-3 sm:grid-cols-[repeat(auto-fill,minmax(520px,1fr))]",
          @loading? && @count != nil && "opacity-60 transition-opacity"
        ]}
      >
        <.link
          :for={{dom_id, deck} <- @streams.decks}
          id={dom_id}
          navigate={~p"/decks/#{deck.id}"}
          class="mc-tile flex items-stretch gap-3 border-2 border-neutral bg-base-200 p-3 shadow-comic sm:gap-4 sm:p-3.5"
        >
          <div class="h-[151px] w-[108px] flex-none border-2 border-neutral shadow-comic-sm">
            <.mc_card
              name={deck.hero_name}
              aspect={:hero}
              image_url={deck.identity_image}
              gradient_from={deck.gradient_from}
              gradient_to={deck.gradient_to}
              size="md"
              show_cost={false}
            />
          </div>

          <div class="flex min-w-0 flex-1 flex-col gap-3 sm:flex-row sm:items-stretch sm:gap-4">
            <div class="flex min-w-0 flex-1 flex-col">
              <div class="flex flex-wrap items-center gap-1.5">
                <span
                  :for={a <- deck.aspects}
                  class={[
                    "border-2 bg-black px-2 py-0.5 font-barlow-condensed text-[11px] font-bold uppercase tracking-[0.08em]",
                    a.text,
                    a.border
                  ]}
                >
                  {a.label}
                </span>
                <span class="border-2 border-neutral bg-black px-2 py-0.5 font-barlow-condensed text-[11px] font-bold uppercase tracking-[0.08em] text-base-content/70">
                  {deck.source_label}
                </span>
              </div>

              <div class="mt-2 break-words font-anton text-[26px] uppercase leading-[0.95]">
                {deck.title}
              </div>

              <div
                :if={deck.tagline}
                class="mt-1.5 break-words font-barlow text-[14px] leading-[1.42] text-base-content/60"
              >
                {deck.tagline}
              </div>

              <div :if={deck.author} class="mt-auto flex items-center gap-2 pt-3">
                <.avatar name={deck.author} url={deck.author_avatar} />
                <span class="font-barlow-condensed text-[13px] font-bold text-primary">
                  {deck.author}
                </span>
              </div>
            </div>

            <div class="flex flex-none items-center gap-4 border-t-2 border-neutral pt-3 sm:w-[120px] sm:flex-col sm:items-start sm:justify-center sm:gap-2 sm:border-l-2 sm:border-t-0 sm:pl-4 sm:pt-0">
              <.uniqueness_meter percentile={deck.uniqueness} class="w-[110px] sm:w-full" />
              <div>
                <div class="font-anton text-[26px] leading-none">{deck.total_card_count}</div>
                <div class="mt-1 font-barlow-condensed text-[11px] font-bold uppercase tracking-[0.1em] text-base-content/50">
                  Cards
                </div>
              </div>
              <div class="ml-auto font-ibm-mono text-[11px] leading-[1.5] text-base-content/40 sm:ml-0">
                {deck.updated}
              </div>
            </div>
          </div>
        </.link>
      </div>

      <!-- empty state -->
      <.panel
        :if={@count == 0}
        class="mt-2 border-dashed !border-[#2a2a30] px-6 py-12 text-center !shadow-none"
      >
        <div class="font-bangers text-[30px] tracking-[0.02em] text-primary">No decks found</div>
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
    socket =
      socket
      |> assign(:page_title, "Browse Decks")
      |> assign(:query, "")
      |> assign(:search_diagnostics, [])
      |> assign(:sort, "new")
      |> assign(:filters_open?, false)
      |> assign(:filter_count, 0)
      # nil until the first async load lands — drives the loading/skeleton UI.
      |> assign(:total, nil)
      |> assign(:count, nil)
      |> assign(:sort_options, @sorts)
      |> assign(:offset, 0)
      |> assign(:end_of_timeline?, false)
      |> assign(:req_id, 0)
      |> assign(:loading?, true)
      |> assign(:scroll_restore_pending?, false)
      |> stream(:decks, [])

    {:ok, socket}
  end

  # Filters live in the URL — as the query string itself, plus a sidecar
  # `sort` param (sorting isn't a filter, so it stays out of the query
  # language) — so back/forward and shared links restore them. The initial
  # data load also starts here — only on the connected mount (req_id == 0
  # guards the first pass); the static render just paints the shell.
  @impl true
  def handle_params(params, _uri, socket) do
    query = params["query"] || ""
    sort = if params["sort"] in @sort_keys, do: params["sort"], else: "new"

    case legacy_filter_query(query, params, socket.assigns.current_user) do
      nil ->
        changed? = query != socket.assigns.query or sort != socket.assigns.sort

        socket =
          assign(socket,
            query: query,
            sort: sort,
            search_diagnostics: search_diagnostics(query),
            filter_count: FormSync.active_count(query, Sanctum.Search.DeckFields)
          )

        socket =
          if connected?(socket) and (changed? or socket.assigns.req_id == 0),
            do: reset_and_load(socket),
            else: socket

        {:noreply, socket}

      translated ->
        {:noreply,
         push_patch(socket,
           to: decks_path(socket.assigns, query: translated, sort: sort),
           replace: true
         )}
    end
  end

  # Pre-filter-sheet URLs carried ?aspect= / ?hero_id= / ?mine= params. Fold
  # them into the query string once and re-patch to the canonical URL.
  defp legacy_filter_query(query, params, current_user) do
    fields =
      %{}
      |> put_legacy_aspect(params["aspect"])
      |> put_legacy_mine(params["mine"], current_user)
      |> put_legacy_hero(params["hero_id"])

    if fields == %{},
      do: nil,
      else: FormSync.update(query, Sanctum.Search.DeckFields, fields)
  end

  defp put_legacy_aspect(fields, aspect) when is_binary(aspect) and aspect != "all" do
    valid = Sanctum.Search.Registry.lookup(Sanctum.Search.DeckFields, "aspect").values
    if aspect in valid, do: Map.put(fields, "aspect", [aspect]), else: fields
  end

  defp put_legacy_aspect(fields, _aspect), do: fields

  defp put_legacy_mine(fields, "true", %{id: _}), do: Map.put(fields, "mine", "true")
  defp put_legacy_mine(fields, _mine, _user), do: fields

  # A legacy hero_id UUID becomes a hero:"<display name>" clause.
  defp put_legacy_hero(fields, hero_id) when is_binary(hero_id) and hero_id != "all" do
    with {:ok, _} <- Ecto.UUID.cast(hero_id),
         {:ok, hero} <- Ash.get(Sanctum.Heroes.Hero, hero_id, load: [:display_name]) do
      Map.put(fields, "hero", hero.display_name)
    else
      _ -> fields
    end
  end

  defp put_legacy_hero(fields, _hero_id), do: fields

  # `replace: true` so typing doesn't spam a history entry per keystroke.
  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, push_patch(socket, to: decks_path(socket.assigns, query: query), replace: true)}
  end

  # Autocomplete for the query input: the QueryInput hook pushes the raw
  # value + cursor and renders whatever we reply with.
  def handle_event("suggest", %{"value" => value, "cursor" => cursor}, socket)
      when is_binary(value) and is_integer(cursor) do
    {:reply, Sanctum.Search.Suggest.suggest(value, cursor, Sanctum.Search.DeckFields), socket}
  end

  def handle_event("suggest", _params, socket), do: {:reply, %{items: []}, socket}

  def handle_event("toggle_filters", _params, socket) do
    {:noreply, update(socket, :filters_open?, &(!&1))}
  end

  # A filter-sheet change: splice the submitted controls back into the query
  # string (the sidecar sort radio rides along in the same form) and re-enter
  # the normal search path (URL → handle_params → load).
  def handle_event("filters_change", params, socket) do
    fields = FormSync.fields_from_params(params, Sanctum.Search.DeckFields)
    query = FormSync.update(socket.assigns.query, Sanctum.Search.DeckFields, fields)
    sort = if params["sort"] in @sort_keys, do: params["sort"], else: socket.assigns.sort

    {:noreply,
     push_patch(socket, to: decks_path(socket.assigns, query: query, sort: sort), replace: true)}
  end

  def handle_event("restore-scroll", %{"offset" => offset}, socket) do
    {:noreply, InfiniteScroll.restore_scroll(socket, offset, @page_size, &start_load/3)}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/decks")}
  end

  def handle_event("next-page", _params, socket) do
    {:noreply, InfiniteScroll.next_page(socket, @page_size, &start_load/3)}
  end

  @impl true
  def handle_async(:load_decks, {:ok, result}, socket) do
    %{req: req, offset: offset, reset?: reset?, page: page, total: total} = result

    # A newer filter/search/page request has since fired; drop these stale
    # results so out-of-order completions can't clobber the current view.
    if req == socket.assigns.req_id do
      socket =
        socket
        |> assign(:offset, offset)
        |> assign(:end_of_timeline?, !page.more?)
        |> assign(:loading?, false)
        |> maybe_assign_total(total)
        |> maybe_assign_count(reset?, page.count)
        |> stream(:decks, Enum.map(page.results, &deck_view(&1, socket.assigns.timezone)),
          reset: reset?
        )

      {:noreply, InfiniteScroll.maybe_confirm_scroll_restore(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:load_decks, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:loading?, false)
     |> put_flash(:error, "Couldn’t load decks: #{inspect(reason)}")}
  end

  # A user-initiated reset (filter/search change) cancels any in-flight scroll
  # restore — the saved position belongs to the previous result set.
  defp reset_and_load(socket) do
    socket
    |> assign(:scroll_restore_pending?, false)
    |> start_load(0, reset: true)
  end

  # Kick off the browse read off the socket so the connected mount returns the
  # shell immediately.
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
    # `total` is the full unfiltered catalog size. It's fetched independently
    # (not read off the first page's count) so it stays accurate even when the
    # LiveView first loads with filters already applied in the URL.
    fetch_total? = is_nil(socket.assigns.total)

    socket
    |> assign(:req_id, req)
    |> assign(:loading?, true)
    |> start_async(:load_decks, fn ->
      page =
        Sanctum.Decks.Deck
        |> Ash.Query.for_read(:browse, filters, actor: actor)
        |> Ash.read!(page: [limit: limit, offset: query_offset, count: reset?])

      total = if fetch_total?, do: load_total(actor), else: nil

      %{req: req, offset: offset, reset?: reset?, page: page, total: total}
    end)
  end

  # Full unfiltered catalog size for the "/ N decks" denominator.
  defp load_total(actor) do
    Sanctum.Decks.Deck
    |> Ash.Query.for_read(:browse, %{}, actor: actor)
    |> Ash.count!()
  end

  # /decks path carrying the current (or overridden) filters, omitting defaults.
  defp decks_path(assigns, overrides) do
    f = Map.merge(filters(assigns), Map.new(overrides))

    params =
      Enum.reject(
        [query: f.query, sort: f.sort],
        fn {k, v} ->
          case k do
            :query -> v == ""
            :sort -> v == "new"
          end
        end
      )

    ~p"/decks?#{params}"
  end

  # `total` (the unfiltered catalog size) is fetched once via `load_total/1` and
  # then left untouched. nil means this load didn't refetch it.
  defp maybe_assign_total(socket, nil), do: socket
  defp maybe_assign_total(socket, total), do: assign(socket, :total, total)

  # `page.count` is only queried on reset loads (count: reset?) — it's the
  # filtered visible count, distinct from the unfiltered `total`.
  defp maybe_assign_count(socket, false, _count), do: socket
  defp maybe_assign_count(socket, true, count), do: assign(socket, :count, count)

  defp filters(a) do
    %{query: a.query, sort: a.sort}
  end

  # Advisory parse/compile problems shown under the query input ("unknown
  # field…", "did you mean…"). The query still runs with the bad part dropped.
  defp search_diagnostics(query) when is_binary(query) and query != "" do
    Sanctum.Search.compile(query, Sanctum.Search.DeckFields).diagnostics
  end

  defp search_diagnostics(_query), do: []

  # Builds the row display map from a loaded Deck.
  defp deck_view(deck, timezone) do
    hero = deck.hero
    author = DeckCards.author(deck)
    {gradient_from, gradient_to} = DeckCards.hero_gradient(hero)

    %{
      id: deck.id,
      title: deck.title,
      hero_name: hero.display_name,
      identity_image: DeckCards.identity_image(hero),
      gradient_from: gradient_from,
      gradient_to: gradient_to,
      aspects: DeckCards.aspect_badges(deck.aspects),
      source_label: DeckCards.source_label(deck.source),
      tagline: excerpt(deck.description_md),
      author: author && author.name,
      author_avatar: author && author.avatar,
      total_card_count: deck.total_card_count || 0,
      card_row_count: deck.card_row_count || 0,
      uniqueness: deck.uniqueness_percentile,
      updated: format_date(deck.mcdb_date_update || deck.updated_at, timezone)
    }
  end

  # Turn description markdown into a short plain-text teaser.
  defp excerpt(md) when is_binary(md) and md != "" do
    text =
      md
      |> String.replace(~r/\[([^\]]+)\]\([^)]*\)/, "\\1")
      |> String.replace(~r/[#>*_`~]/, "")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    cond do
      text == "" -> nil
      String.length(text) > 140 -> String.slice(text, 0, 140) <> "…"
      true -> text
    end
  end

  defp excerpt(_), do: nil

  defp format_date(%DateTime{} = dt, timezone),
    do: dt |> Timezone.to_local(timezone) |> Calendar.strftime("%b %-d, %Y")

  defp format_date(_value, _timezone), do: ""
end
