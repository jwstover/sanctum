defmodule SanctumWeb.DeckLive.Index do
  @moduledoc """
  Public "Deck Browser" — a feed of decks filterable by name/hero, aspect, and
  hero, with Newest / A–Z sorting. The comic-dossier counterpart to the admin
  deck table.
  """
  use SanctumWeb, :live_view

  require Ash.Query

  alias SanctumWeb.Components.Card, as: CardComponent

  @page_size 24

  @aspects [
    {"all", "All", nil},
    {"aggression", "Aggression", "bg-aspect-aggression"},
    {"justice", "Justice", "bg-aspect-justice"},
    {"leadership", "Leadership", "bg-aspect-leadership"},
    {"protection", "Protection", "bg-aspect-protection"},
    {"pool", "Pool", "bg-aspect-pool"},
    {"basic", "Basic", "bg-aspect-basic"}
  ]

  @sorts [{"new", "Newest"}, {"title", "A–Z"}]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:decks}>
      <.header>
        Browse Decks
        <:subtitle>
          Every deck in the vault. Filter by hero or aspect, then open one for the full list.
        </:subtitle>
      </.header>

      <!-- search + count -->
      <div class="mb-3 flex flex-wrap items-center gap-2.5">
        <form id="deck-search" phx-change="search" class="relative min-w-[260px] flex-1">
          <span class="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-[17px] text-base-content/40">
            ⌕
          </span>
          <input
            type="text"
            name="query"
            value={@query}
            phx-debounce="200"
            autocomplete="off"
            placeholder="Search decks or heroes…"
            class="w-full border-[2.5px] border-line bg-black px-3.5 py-2.5 pl-[38px] font-barlow text-[15px] text-base-content outline-none focus:border-primary"
          />
        </form>
        <div class="whitespace-nowrap font-anton text-[15px] uppercase tracking-[0.05em]">
          {@count} <span class="text-base-content/45">/ {@total} decks</span>
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
        <form id="deck-hero-filter" phx-change="filter_hero" class="ml-auto min-w-[200px]">
          <select
            name="hero_id"
            class="w-full border-[2.5px] border-line bg-black px-3 py-2 font-barlow-condensed text-[14px] font-bold uppercase tracking-[0.04em] text-base-content outline-none focus:border-primary"
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

      <!-- feed -->
      <div
        id="deck-feed"
        phx-update="stream"
        phx-viewport-bottom={!@end_of_timeline? && "next-page"}
        class="grid grid-cols-[repeat(auto-fill,minmax(520px,1fr))] items-start gap-3"
      >
        <.link
          :for={{dom_id, deck} <- @streams.decks}
          id={dom_id}
          navigate={~p"/decks/#{deck.id}"}
          class="mc-tile flex items-stretch gap-4 border-2 border-neutral bg-base-200 p-3.5 shadow-comic"
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

            <div class="mt-2 font-anton text-[26px] uppercase leading-[0.95]">{deck.title}</div>

            <div
              :if={deck.tagline}
              class="mt-1.5 font-barlow text-[14px] leading-[1.42] text-base-content/60"
            >
              {deck.tagline}
            </div>

            <div :if={deck.author} class="mt-auto flex items-center gap-2 pt-3">
              <span class="flex size-[26px] items-center justify-center rounded-full border-2 border-neutral bg-primary font-bangers text-sm text-primary-content">
                {deck.author_initial}
              </span>
              <span class="font-barlow-condensed text-[13px] font-bold text-primary">
                {deck.author}
              </span>
            </div>
          </div>

          <div class="flex flex-none flex-col justify-center gap-2 border-l-2 border-neutral pl-4">
            <div>
              <div class="font-anton text-[26px] leading-none">{deck.total_card_count}</div>
              <div class="mt-1 font-barlow-condensed text-[11px] font-bold uppercase tracking-[0.1em] text-base-content/50">
                Cards
              </div>
            </div>
            <div class="font-barlow text-[13px] text-base-content/55">
              {deck.card_row_count} unique
            </div>
            <div class="font-ibm-mono text-[11px] leading-[1.5] text-base-content/40">
              {deck.updated}
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
    total = count_decks(socket, %{})

    {:ok,
     socket
     |> assign(:page_title, "Browse Decks")
     |> assign(:query, "")
     |> assign(:sort, "new")
     |> assign(:aspect, "all")
     |> assign(:hero_id, "all")
     |> assign(:total, total)
     |> assign(:count, total)
     |> assign(:aspect_options, @aspects)
     |> assign(:sort_options, @sorts)
     |> assign(:hero_options, load_hero_options())
     |> assign(:offset, 0)
     |> assign(:end_of_timeline?, false)
     |> stream(:decks, [])
     |> load_page(0, reset: true)}
  end

  # {id, hero_name} for every hero that has at least one deck, sorted by name.
  # TODO: optimize with a distinct query if the deck count grows large.
  defp load_hero_options do
    Sanctum.Decks.Deck
    |> Ash.Query.load(:hero)
    |> Ash.read!()
    |> Enum.map(& &1.hero)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.hero_name)
    |> Enum.map(&{&1.id, &1.hero_name})
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, socket |> assign(:query, query) |> reset_and_load()}
  end

  def handle_event("sort", %{"key" => key}, socket) do
    {:noreply, socket |> assign(:sort, key) |> reset_and_load()}
  end

  def handle_event("filter_aspect", %{"key" => key}, socket) do
    {:noreply, socket |> assign(:aspect, key) |> reset_and_load()}
  end

  def handle_event("filter_hero", %{"hero_id" => hero_id}, socket) do
    {:noreply, socket |> assign(:hero_id, hero_id) |> reset_and_load()}
  end

  def handle_event("clear", _params, socket) do
    {:noreply,
     socket
     |> assign(query: "", aspect: "all", hero_id: "all", sort: "new")
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
      Sanctum.Decks.Deck
      |> Ash.Query.for_read(:browse, filters(socket.assigns),
        actor: socket.assigns[:current_user]
      )
      |> Ash.read!(page: [limit: @page_size, offset: offset, count: reset?])

    socket
    |> assign(:offset, offset)
    |> assign(:end_of_timeline?, !page.more?)
    |> then(fn s -> if reset?, do: assign(s, :count, page.count), else: s end)
    |> stream(:decks, Enum.map(page.results, &deck_view/1), reset: reset?)
  end

  defp count_decks(socket, extra) do
    Sanctum.Decks.Deck
    |> Ash.Query.for_read(:browse, Map.merge(%{sort: "new"}, extra),
      actor: socket.assigns[:current_user]
    )
    |> Ash.read!(page: [limit: 1, offset: 0, count: true])
    |> Map.get(:count)
  end

  defp filters(a) do
    %{query: a.query, aspect: a.aspect, hero_id: a.hero_id, sort: a.sort}
  end

  # Builds the row display map from a loaded Deck.
  defp deck_view(deck) do
    hero = deck.hero
    author = author(deck)

    %{
      id: deck.id,
      title: deck.title,
      hero_name: hero.hero_name,
      identity_image: identity_image(hero),
      gradient_from: hero.primary_color || elem(CardComponent.fallback_gradient(hero.set), 0),
      gradient_to: hero.secondary_color || elem(CardComponent.fallback_gradient(hero.set), 1),
      aspects: aspect_badges(deck.aspects),
      source_label: source_label(deck.source),
      tagline: excerpt(deck.description_md),
      author: author,
      author_initial: author_initial(author),
      total_card_count: deck.total_card_count || 0,
      card_row_count: deck.card_row_count || 0,
      updated: format_date(deck.updated_at)
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

  defp author(%{mcdb_user: %{username: username}}) when is_binary(username) and username != "",
    do: "@" <> username

  defp author(%{mcdb_user: %{mcdb_user_id: id}}) when not is_nil(id), do: "mcdb ##{id}"
  defp author(%{owner: %{email: email}}) when is_binary(email), do: email
  defp author(_), do: nil

  defp author_initial(nil), do: "?"

  defp author_initial(author),
    do: author |> String.trim_leading("@") |> String.first() |> String.upcase()

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
