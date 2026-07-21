defmodule SanctumWeb.DeckLive.Show do
  @moduledoc """
  Public deck detail — a comic-dossier "decklist" view: a cover with the hero
  identity card + deck meta, the writeup, and the card list grouped by type.
  """
  use SanctumWeb, :live_view

  import SanctumWeb.Components.CardSideTile
  import SanctumWeb.Components.DeckCards

  alias SanctumWeb.Components.DeckCards

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:decks}>
      <div id="scroll-restore" phx-hook="ScrollRestore"></div>
      <.card_view_pref />
      <!-- first-load skeleton -->
      <div :if={@deck == nil}>
        <div class="mb-6 h-9 w-1/2 max-w-md animate-pulse bg-base-300"></div>
        <.detail_skeleton />
      </div>

      <div :if={@deck != nil}>
        <header class="mb-6 border-b-[3px] border-neutral pb-4">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between sm:gap-6">
            <div class="order-2 min-w-0 sm:order-1">
              <h1 class="font-anton text-3xl uppercase leading-[0.9] tracking-[0.005em] md:text-[42px]">
                {@deck.title}
              </h1>
              <p class="mt-2 font-barlow text-[15px] text-base-content/60">
                {@cover.hero_name}<span :if={@cover.author}> · by {@cover.author}</span>
              </p>
            </div>
            <div class="order-1 flex flex-none items-center gap-2.5 sm:order-2">
              <.button
                :if={owner?(@deck, @current_user)}
                variant="primary"
                navigate={~p"/decks/#{@deck.id}/build"}
              >
                <.icon name="hero-pencil-square" /> Edit Deck
              </.button>
              <.button
                :if={mcdb_url(@deck)}
                href={mcdb_url(@deck)}
                target="_blank"
                rel="noopener noreferrer"
              >
                <.icon name="hero-arrow-top-right-on-square" /> MarvelCDB
              </.button>
              <.back_button fallback={~p"/decks"} />
            </div>
          </div>
        </header>

        <div class="space-y-5">
          <!-- cover -->
          <.panel class="relative flex flex-col gap-5 overflow-hidden p-4 sm:flex-row sm:items-start">
            <div
              class="h-[330px] w-[236px] flex-none self-center border-2 border-neutral shadow-comic sm:self-start"
              style="transform:rotate(-1.5deg);"
            >
              <.mc_card
                name={@cover.hero_name}
                aspect={:hero}
                image_url={@cover.identity_image}
                gradient_from={@cover.gradient_from}
                gradient_to={@cover.gradient_to}
                size="lg"
                show_cost={false}
              />
            </div>

            <div class="flex min-w-0 flex-1 flex-col">
              <div class="font-ibm-mono text-[11px] uppercase tracking-[0.25em] text-primary">
                {@cover.source_label} · {@cover.hero_name}
              </div>
              <h1 class="mt-1.5 font-anton text-[34px] uppercase leading-[0.9] [text-wrap:balance] sm:text-[46px] sm:leading-[0.88]">
                {@deck.title}
              </h1>

              <div class="mt-3 flex flex-wrap items-center gap-1.5">
                <span
                  :for={a <- @cover.aspects}
                  class={[
                    "border-2 bg-black px-2 py-0.5 font-barlow-condensed text-[11px] font-bold uppercase tracking-[0.08em]",
                    a.text,
                    a.border
                  ]}
                >
                  {a.label}
                </span>
              </div>

              <div class="mt-4 flex flex-wrap items-end gap-x-6 gap-y-3">
                <div>
                  <div class="font-anton text-[30px] leading-none">{@cover.total_cards}</div>
                  <div class="mt-1 font-barlow-condensed text-[11px] font-bold uppercase tracking-[0.1em] text-base-content/50">
                    Cards
                  </div>
                </div>
                <div>
                  <div class="font-anton text-[30px] leading-none">{@cover.unique_cards}</div>
                  <div class="mt-1 font-barlow-condensed text-[11px] font-bold uppercase tracking-[0.1em] text-base-content/50">
                    Unique
                  </div>
                </div>
                <.uniqueness_meter percentile={@cover.uniqueness} size="lg" class="self-center" />
                <div :if={@cover.author} class="flex items-center gap-2 self-center">
                  <.avatar name={@cover.author} url={@cover.author_avatar} size="md" />
                  <span class="font-barlow-condensed text-[13px] font-bold text-primary">
                    {@cover.author}
                  </span>
                </div>
              </div>
            </div>
            <div class="absolute inset-x-0 bottom-0 h-1.5" style={"background:#{@cover.gradient_to};"}>
            </div>
          </.panel>

          <!-- body: writeup + card list -->
          <div class="grid items-start gap-5 lg:grid-cols-[1.4fr_1fr]">
            <.panel class="min-w-0 p-5">
              <div class="mb-3 font-ibm-mono text-[10px] uppercase tracking-[0.2em] text-base-content/50">
                Deck Notes
              </div>
              <div :if={@writeup} id="deck-writeup" phx-hook="CardLinkPreview" class="space-y-4">
                <div :for={seg <- @writeup}>
                  <div :if={seg.kind == :inline} class="deck-writeup">{seg.html}</div>
                  <iframe
                    :if={seg.kind == :rich}
                    title="Deck writeup"
                    sandbox=""
                    referrerpolicy="no-referrer"
                    loading="lazy"
                    class="deck-writeup-frame"
                    srcdoc={seg.srcdoc}
                  ></iframe>
                </div>
              </div>
              <div :if={!@writeup} class="font-barlow text-[14px] italic text-base-content/45">
                No writeup for this deck.
              </div>
            </.panel>

            <div class="min-w-0 space-y-5">
              <.panel class="p-4">
                <div class="mb-3 flex items-center gap-2 border-b-2 border-neutral pb-2">
                  <div class="font-anton text-[17px] uppercase tracking-[0.05em]">In This Deck</div>
                  <div class="ml-auto font-ibm-mono text-[11px] text-base-content/45">
                    {@cover.total_cards} cards<span
                      :if={@owned_summary}
                      class="text-primary"
                    > · you own {@owned_summary.owned} / {@owned_summary.total}</span>
                  </div>
                  <div class="flex border-2 border-neutral" role="group" aria-label="Card display">
                    <.view_toggle_button
                      view="images"
                      icon="hero-squares-2x2"
                      label="Image view"
                      active={@card_view == "images"}
                    />
                    <.view_toggle_button
                      view="list"
                      icon="hero-list-bullet"
                      label="List view"
                      active={@card_view == "list"}
                    />
                  </div>
                </div>

                <div :for={g <- @groups} class="mb-4 last:mb-0">
                  <div class="mb-2 font-anton text-[12px] uppercase tracking-[0.06em] text-primary">
                    {g.name} · {g.count}
                  </div>
                  <div
                    :if={@card_view == "images"}
                    class="grid grid-cols-[repeat(auto-fill,minmax(72px,1fr))] gap-2"
                  >
                    <.link
                      :for={c <- g.cards}
                      navigate={~p"/cards/#{c.card_id}"}
                      class="relative h-[101px] border-2 border-neutral shadow-comic-sm"
                    >
                      <.mc_card
                        name={c.name}
                        cost={c.cost}
                        aspect={c.aspect_key}
                        image_url={c.image_url}
                        gradient_from={c.gradient_from}
                        gradient_to={c.gradient_to}
                        qty={c.qty}
                        size="sm"
                        show_cost={false}
                      />
                      <span
                        :if={c.owned == true}
                        title="In your collection"
                        class="absolute bottom-0.5 right-0.5 z-[3] flex size-4 items-center justify-center rounded-[4px] bg-base-100/75 text-success"
                      >
                        <.icon name="hero-check" class="size-3" />
                      </span>
                    </.link>
                  </div>
                  <div :if={@card_view == "list"} class="divide-y divide-neutral/50">
                    <.link
                      :for={c <- g.cards}
                      navigate={~p"/cards/#{c.card_id}"}
                      class="flex items-center gap-2 px-1 py-1 hover:bg-base-200"
                    >
                      <.row_cost cost={c.cost} />
                      <.icon
                        :if={c.aspect_key == :hero}
                        name="hero-user-solid"
                        class="size-3 flex-none text-aspect-hero"
                      />
                      <span :if={c.aspect_key != :hero} class={["size-2.5 flex-none", c.aspect_bg]}></span>
                      <span class="min-w-0 truncate font-barlow-condensed text-[14px] font-semibold text-base-content/85">
                        {c.name}
                      </span>
                      <span :if={c.owned == true} title="In your collection" class="flex-none">
                        <.icon name="hero-check" class="size-3 text-success" />
                      </span>
                      <span class="flex-1"></span>
                      <span class="flex-none font-ibm-mono text-[11px] text-base-content/50">
                        {c.qty}×
                      </span>
                      <span class="flex w-8 flex-none items-center justify-end gap-1">
                        <span
                          :for={{color_class, glyph} <- c.pips}
                          class={["font-champions text-[14px] leading-none", color_class]}
                        >
                          {glyph}
                        </span>
                      </span>
                    </.link>
                  </div>
                </div>
              </.panel>

              <!-- similar decks -->
              <.panel :if={@similar != []} class="p-4">
                <div class="mb-3 font-ibm-mono text-[10px] uppercase tracking-[0.2em] text-base-content/50">
                  Similar Decks
                </div>
                <div class="space-y-2">
                  <.link
                    :for={s <- @similar}
                    navigate={~p"/decks/#{s.id}"}
                    class="mc-tile flex items-center gap-3 border-2 border-neutral bg-black p-2.5 shadow-comic-sm"
                  >
                    <div class="min-w-0 flex-1">
                      <div class="truncate font-anton text-[16px] uppercase leading-tight">
                        {s.title}
                      </div>
                      <div class="mt-1 flex flex-wrap gap-1">
                        <span
                          :for={a <- s.aspects}
                          class={[
                            "border bg-base-200 px-1.5 font-barlow-condensed text-[10px] font-bold uppercase tracking-[0.06em]",
                            a.text,
                            a.border
                          ]}
                        >
                          {a.label}
                        </span>
                      </div>
                    </div>
                    <div class="flex-none text-right">
                      <div class="font-anton text-[20px] leading-none text-primary">{s.match}%</div>
                      <div class="font-barlow-condensed text-[10px] font-bold uppercase tracking-[0.1em] text-base-content/45">
                        Match
                      </div>
                    </div>
                  </.link>
                </div>
              </.panel>

              <!-- details -->
              <.panel class="p-4">
                <div class="mb-3 font-ibm-mono text-[10px] uppercase tracking-[0.2em] text-base-content/50">
                  Details
                </div>
                <div class="grid grid-cols-2 gap-x-6 gap-y-3">
                  <.meta label="Source" value={@cover.source_label} />
                  <div :if={mcdb_url(@deck)}>
                    <div class="font-ibm-mono text-[10px] uppercase tracking-[0.2em] text-base-content/45">
                      MarvelCDB
                    </div>
                    <a
                      href={mcdb_url(@deck)}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="mt-0.5 inline-flex items-center gap-1 font-barlow-condensed text-[15px] font-semibold text-primary hover:underline"
                    >
                      {@deck.mcdb_type}/{@deck.mcdb_id}
                      <.icon name="hero-arrow-top-right-on-square" class="size-3" />
                    </a>
                  </div>
                  <.meta :if={@deck.version} label="Version" value={@deck.version} />
                  <.meta :if={@deck.tags} label="Tags" value={@deck.tags} />
                </div>
              </.panel>
            </div>
          </div>
        </div>
      </div>

      <!-- hover preview for writeup card links; the CardLinkPreview hook
           positions and toggles it, LiveView only swaps the tile inside -->
      <div
        id="card-link-preview"
        class="pointer-events-none fixed left-0 top-0 z-50 hidden w-[480px] max-w-[calc(100vw-16px)]"
      >
        <.card_side_tile :if={@card_preview} side={@card_preview} />
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp meta(assigns) do
    ~H"""
    <div :if={@value not in [nil, ""]}>
      <div class="font-ibm-mono text-[10px] uppercase tracking-[0.2em] text-base-content/45">
        {@label}
      </div>
      <div class="mt-0.5 font-barlow-condensed text-[15px] font-semibold">{@value}</div>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Deck")
      # nil until the async load lands — drives the loading/skeleton UI.
      |> assign(:deck, nil)
      |> assign(:cover, nil)
      |> assign(:groups, [])
      |> assign(:similar, [])
      |> assign(:writeup, nil)
      |> assign(:card_view, "images")
      |> assign(:scroll_restore_pending?, false)
      |> assign(:owned_summary, nil)
      |> assign(:card_preview, nil)
      # set -> gradient palette for preview tiles, fetched once on first hover
      |> assign(:hero_colors, nil)

    actor = socket.assigns[:current_user]

    # Skip the (heavy) deck load on the static render; it runs asynchronously
    # once the socket connects so the shell paints immediately.
    socket =
      if connected?(socket),
        do: start_async(socket, :load_deck, fn -> load_deck(id, actor) end),
        else: socket

    {:ok, socket}
  end

  @impl true
  def handle_event(event, params, socket)
      when event in ["set_card_view", "restore_card_view"] do
    {:noreply, DeckCards.handle_card_view_event(event, params, socket)}
  end

  # Pushed by the CardLinkPreview hook when a writeup card link is hovered.
  # Loads the linked card's primary face and renders the same tile the card
  # pool shows into the #card-link-preview popover; the reply tells the hook
  # the tile is ready to position. Unresolvable ids reply with an error so the
  # hook keeps the popover hidden.
  def handle_event("preview_card", %{"id" => id}, socket) do
    actor = socket.assigns[:current_user]
    side_loads = if actor, do: [:owned], else: []

    case Ash.get(Sanctum.Games.Card, id, actor: actor, load: [primary_side: side_loads]) do
      {:ok, %{primary_side: %Sanctum.Games.CardSide{} = side} = card} ->
        hero_colors = socket.assigns.hero_colors || Sanctum.Heroes.hero_color_map()

        {:reply, %{},
         socket
         |> assign(:hero_colors, hero_colors)
         |> assign(:card_preview, side_view(%{side | card: card}, hero_colors))}

      _ ->
        {:reply, %{error: true}, socket}
    end
  end

  # Pushed by the ScrollRestore hook when the user arrives with a saved scroll
  # position. The page renders asynchronously, so hold the confirmation until
  # the deck load lands and the content exists at its full height.
  def handle_event("restore-scroll", _params, socket) do
    if socket.assigns.deck do
      {:noreply, push_event(socket, "sanctum:scroll-restore", %{})}
    else
      {:noreply, assign(socket, :scroll_restore_pending?, true)}
    end
  end

  @impl true
  def handle_async(:load_deck, {:ok, {:ok, data}}, socket) do
    socket =
      socket
      |> assign(:page_title, data.deck.title)
      |> assign(:deck, data.deck)
      |> assign(:cover, data.cover)
      |> assign(:groups, data.groups)
      |> assign(:owned_summary, data.owned_summary)
      |> assign(:similar, data.similar)
      |> assign(:writeup, data.writeup)

    socket =
      if socket.assigns.scroll_restore_pending? do
        socket
        |> assign(:scroll_restore_pending?, false)
        |> push_event("sanctum:scroll-restore", %{})
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_async(:load_deck, {:ok, :not_found}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Deck not found.")
     |> push_navigate(to: ~p"/decks")}
  end

  def handle_async(:load_deck, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Couldn’t load deck: #{inspect(reason)}")
     |> push_navigate(to: ~p"/decks")}
  end

  # Load the deck with its cards and derive the cover, grouped card list, similar
  # decks, and rendered writeup. Returns `:not_found` for an unknown id so
  # handle_async can redirect rather than crash the LiveView.
  defp load_deck(id, actor) do
    # Collection status rides the same deck_cards load when signed in.
    card_loads = if actor, do: [:primary_side, :owned], else: [:primary_side]

    case Sanctum.Decks.get_deck(id,
           actor: actor,
           load: [
             :card_row_count,
             :total_card_count,
             :mcdb_user,
             :owner,
             hero: [:display_name, :hero_side, card: [:primary_side]],
             deck_cards: [card: card_loads]
           ]
         ) do
      {:ok, deck} ->
        hero_gradient = DeckCards.hero_gradient(deck.hero)
        card_views = Enum.map(deck.deck_cards, &DeckCards.card_view(&1, hero_gradient))
        groups = DeckCards.group_by_type(card_views)

        {:ok,
         %{
           deck: deck,
           cover: cover_view(deck, hero_gradient),
           groups: groups,
           owned_summary: owned_summary(card_views, actor),
           similar: similar_views(deck),
           writeup: Sanctum.Decks.Writeup.render(deck.description_md)
         }}

      {:error, _} ->
        :not_found
    end
  end

  # "You own X / Y" across the deck's card copies; nil (no line) for anonymous.
  defp owned_summary(_card_views, nil), do: nil

  defp owned_summary(card_views, _actor) do
    %{
      owned: card_views |> Enum.filter(&(&1.owned == true)) |> Enum.sum_by(& &1.qty),
      total: Enum.sum_by(card_views, & &1.qty)
    }
  end

  # Same-hero decks that share the most chosen cards with this one.
  defp similar_views(deck) do
    deck
    |> Sanctum.Decks.Uniqueness.similar_decks(limit: 5)
    |> Enum.map(fn %{deck: d, similarity: sim} ->
      %{
        id: d.id,
        title: d.title,
        aspects: aspect_badges(d.aspects),
        card_count: d.total_card_count || 0,
        match: round(sim * 100)
      }
    end)
  end

  defp cover_view(deck, {gradient_from, gradient_to}) do
    hero = deck.hero
    author = author(deck)

    %{
      hero_name: hero.display_name,
      identity_image: identity_image(hero),
      gradient_from: gradient_from,
      gradient_to: gradient_to,
      aspects: aspect_badges(deck.aspects),
      source_label: source_label(deck.source),
      total_cards: deck.total_card_count || 0,
      unique_cards: deck.card_row_count || 0,
      uniqueness: deck.uniqueness_percentile,
      author: author && author.name,
      author_avatar: author && author.avatar
    }
  end

  # Only native decks are editable, and only by their owner.
  defp owner?(%{source: :native, owner_id: owner_id}, %{id: user_id}) when not is_nil(owner_id),
    do: owner_id == user_id

  defp owner?(_deck, _user), do: false

  # Public MarvelCDB URL for the source deck, when this deck came from there.
  # `decklist` and `deck` are separate id spaces with distinct URL paths.
  defp mcdb_url(%{mcdb_id: id, mcdb_type: :decklist}) when is_binary(id),
    do: "https://marvelcdb.com/decklist/view/#{id}"

  defp mcdb_url(%{mcdb_id: id, mcdb_type: :deck}) when is_binary(id),
    do: "https://marvelcdb.com/deck/view/#{id}"

  defp mcdb_url(_), do: nil
end
