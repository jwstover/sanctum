defmodule SanctumWeb.DeckLive.Index do
  @moduledoc """
  Public "Deck Browser" — a feed of decks filterable by name/hero, aspect, and
  hero, with Newest / A–Z sorting. The comic-dossier counterpart to the admin
  deck table.
  """
  use SanctumWeb, :live_view

  require Ash.Query

  import SanctumWeb.Components.QueryInput

  alias SanctumWeb.Components.Card, as: CardComponent
  alias SanctumWeb.InfiniteScroll

  @page_size 24

  @aspects SanctumWeb.CardFilters.deck_aspect_options()

  @sorts [{"new", "Newest"}, {"unique", "Unique"}, {"title", "A–Z"}]

  @aspect_keys Enum.map(@aspects, &elem(&1, 0))
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
      </.header>

      <!-- search + count -->
      <div class="mb-3">
        <form id="deck-search" phx-change="search" class="flex w-full">
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

      <!-- sort + hero -->
      <div class="mb-2.5 flex flex-wrap items-center gap-2.5">
        <div class="flex gap-1.5">
          <.filter_pill
            :for={{key, label} <- @sort_options}
            active={@sort == key}
            phx-click="sort"
            phx-value-key={key}
          >
            {label}
          </.filter_pill>
        </div>
        <form
          id="deck-hero-filter"
          phx-change="filter_hero"
          class="ml-auto min-w-[180px] flex-1 sm:min-w-[200px] sm:flex-none"
        >
          <select
            name="hero_id"
            class="min-h-[44px] w-full border-[2.5px] border-line bg-black px-3 py-2 font-barlow-condensed text-base font-bold uppercase tracking-[0.04em] text-base-content outline-none focus:border-primary sm:min-h-0 sm:text-[14px]"
          >
            <option value="all" selected={@hero_id == "all"}>All heroes</option>
            <option :for={{id, name} <- @hero_options} value={id} selected={@hero_id == id}>
              {name}
            </option>
          </select>
        </form>
      </div>

      <!-- aspect filters -->
      <div class="mb-6 flex flex-wrap gap-1.5">
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
      |> assign(:aspect, "all")
      |> assign(:hero_id, "all")
      # nil until the first async load lands — drives the loading/skeleton UI.
      |> assign(:total, nil)
      |> assign(:count, nil)
      |> assign(:aspect_options, @aspects)
      |> assign(:sort_options, @sorts)
      |> assign(:hero_options, [])
      |> assign(:offset, 0)
      |> assign(:end_of_timeline?, false)
      |> assign(:req_id, 0)
      |> assign(:loading?, true)
      |> assign(:scroll_restore_pending?, false)
      |> stream(:decks, [])

    {:ok, socket}
  end

  # Filters live in the URL (filter events push_patch here) so back/forward
  # and shared links restore them. The initial data load also starts here —
  # only on the connected mount (req_id == 0 guards the first pass); the
  # static render just paints the shell.
  @impl true
  def handle_params(params, _uri, socket) do
    query = params["query"] || ""
    sort = if params["sort"] in @sort_keys, do: params["sort"], else: "new"
    aspect = if params["aspect"] in @aspect_keys, do: params["aspect"], else: "all"
    hero_id = valid_hero_id(params["hero_id"])

    changed? =
      query != socket.assigns.query or sort != socket.assigns.sort or
        aspect != socket.assigns.aspect or hero_id != socket.assigns.hero_id

    socket =
      assign(socket,
        query: query,
        sort: sort,
        aspect: aspect,
        hero_id: hero_id,
        search_diagnostics: search_diagnostics(query)
      )

    socket =
      if connected?(socket) and (changed? or socket.assigns.req_id == 0),
        do: reset_and_load(socket),
        else: socket

    {:noreply, socket}
  end

  defp valid_hero_id(hero_id) when is_binary(hero_id) do
    case Ecto.UUID.cast(hero_id) do
      {:ok, _} -> hero_id
      :error -> "all"
    end
  end

  defp valid_hero_id(_), do: "all"

  # {id, display_name} for every hero, sorted by name. `display_name` carries
  # the alter ego for same-named heroes (the Black Panthers, the Spider-Men).
  defp load_hero_options do
    Sanctum.Heroes.Hero
    |> Ash.Query.select([:id, :hero_name])
    |> Ash.Query.load(:display_name)
    |> Ash.read!()
    |> Enum.map(&{&1.id, &1.display_name})
    |> Enum.sort_by(fn {_id, name} -> name end)
  end

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

  def handle_event("sort", %{"key" => key}, socket) do
    {:noreply, push_patch(socket, to: decks_path(socket.assigns, sort: key))}
  end

  def handle_event("filter_aspect", %{"key" => key}, socket) do
    {:noreply, push_patch(socket, to: decks_path(socket.assigns, aspect: key))}
  end

  def handle_event("filter_hero", %{"hero_id" => hero_id}, socket) do
    {:noreply, push_patch(socket, to: decks_path(socket.assigns, hero_id: hero_id))}
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
    %{
      req: req,
      offset: offset,
      reset?: reset?,
      page: page,
      hero_options: hero_options,
      total: total
    } = result

    # A newer filter/search/page request has since fired; drop these stale
    # results so out-of-order completions can't clobber the current view.
    if req == socket.assigns.req_id do
      socket =
        socket
        |> assign(:offset, offset)
        |> assign(:end_of_timeline?, !page.more?)
        |> assign(:loading?, false)
        |> maybe_assign_hero_options(hero_options)
        |> maybe_assign_total(total)
        |> maybe_assign_count(reset?, page.count)
        |> stream(:decks, Enum.map(page.results, &deck_view/1), reset: reset?)

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
  # shell immediately. `hero_options` is fetched only once per LiveView (a
  # static hero list) and reused across every subsequent load.
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
    fetch_heroes? = socket.assigns.hero_options == []
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

      hero_options = if fetch_heroes?, do: load_hero_options(), else: nil
      total = if fetch_total?, do: load_total(actor), else: nil

      %{
        req: req,
        offset: offset,
        reset?: reset?,
        page: page,
        hero_options: hero_options,
        total: total
      }
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
        [query: f.query, sort: f.sort, aspect: f.aspect, hero_id: f.hero_id],
        fn {k, v} ->
          case k do
            :query -> v == ""
            :sort -> v == "new"
            _ -> v == "all"
          end
        end
      )

    ~p"/decks?#{params}"
  end

  defp maybe_assign_hero_options(socket, nil), do: socket
  defp maybe_assign_hero_options(socket, options), do: assign(socket, :hero_options, options)

  # `total` (the unfiltered catalog size) is fetched once via `load_total/1` and
  # then left untouched. nil means this load didn't refetch it.
  defp maybe_assign_total(socket, nil), do: socket
  defp maybe_assign_total(socket, total), do: assign(socket, :total, total)

  # `page.count` is only queried on reset loads (count: reset?) — it's the
  # filtered visible count, distinct from the unfiltered `total`.
  defp maybe_assign_count(socket, false, _count), do: socket
  defp maybe_assign_count(socket, true, count), do: assign(socket, :count, count)

  defp filters(a) do
    %{query: a.query, aspect: a.aspect, hero_id: a.hero_id, sort: a.sort}
  end

  # Advisory parse/compile problems shown under the query input ("unknown
  # field…", "did you mean…"). The query still runs with the bad part dropped.
  defp search_diagnostics(query) when is_binary(query) and query != "" do
    Sanctum.Search.compile(query, Sanctum.Search.DeckFields).diagnostics
  end

  defp search_diagnostics(_query), do: []

  # Builds the row display map from a loaded Deck.
  defp deck_view(deck) do
    hero = deck.hero
    author = author(deck)

    %{
      id: deck.id,
      title: deck.title,
      hero_name: hero.display_name,
      identity_image: identity_image(hero),
      gradient_from: hero.primary_color || elem(CardComponent.fallback_gradient(hero.set), 0),
      gradient_to: hero.secondary_color || elem(CardComponent.fallback_gradient(hero.set), 1),
      aspects: aspect_badges(deck.aspects),
      source_label: source_label(deck.source),
      tagline: excerpt(deck.description_md),
      author: author && author.name,
      author_avatar: author && author.avatar,
      total_card_count: deck.total_card_count || 0,
      card_row_count: deck.card_row_count || 0,
      uniqueness: deck.uniqueness_percentile,
      updated: format_date(deck.mcdb_date_update || deck.updated_at)
    }
  end

  defp identity_image(%{hero_side: %{image_url: url}}) when is_binary(url), do: url
  defp identity_image(%{card: %{primary_side: %{image_url: url}}}) when is_binary(url), do: url
  defp identity_image(_), do: nil

  defp aspect_badges([]), do: [aspect_badge(:basic, "Basic")]

  defp aspect_badges(aspects),
    do: Enum.map(aspects, &aspect_badge(&1, &1 |> to_string() |> String.capitalize()))

  defp aspect_badge(aspect, label) do
    ac = CardComponent.aspect_classes(aspect)
    %{label: label, text: ac.text, border: ac.border}
  end

  defp source_label(:marvelcdb), do: "MarvelCDB"
  defp source_label(:native), do: "Native"
  defp source_label(other), do: other |> to_string() |> String.capitalize()

  # Attribution: imported decks credit the MarvelCDB author; native decks
  # credit the owner's claimed username (never their email — the field is
  # policy-hidden). Owners without a username get no attribution row.
  defp author(%{mcdb_user: %{username: username}}) when is_binary(username) and username != "",
    do: %{name: "@" <> username, avatar: nil}

  defp author(%{mcdb_user: %{mcdb_user_id: id}}) when not is_nil(id),
    do: %{name: "mcdb ##{id}", avatar: nil}

  defp author(%{owner: %{username: %Ash.CiString{} = username, avatar_url: avatar}}),
    do: %{name: "@" <> to_string(username), avatar: avatar}

  defp author(_), do: nil

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

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %-d, %Y")
  defp format_date(_), do: ""
end
