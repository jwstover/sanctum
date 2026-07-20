defmodule SanctumWeb.DeckLive.Build do
  @moduledoc """
  The native deckbuilder: a mobile-first card-image grid (search, aspect and
  type pills, infinite scroll) where every tile carries a quantity stepper.
  Quantity changes persist immediately through `Sanctum.Decks`; deck counts
  and advisory legality issues are derived from in-socket state, never from
  stale aggregates. Only the owner of a native deck can build.

  Grid tiles live in a stream; a quantity change re-inserts the affected
  tile (matching dom id, no `at:`) so its badge re-renders in place without
  re-diffing the whole grid.
  """

  use SanctumWeb, :live_view

  require Ash.Query

  import SanctumWeb.Components.QueryInput

  alias Sanctum.Decks
  alias Sanctum.Decks.Legality
  alias SanctumWeb.Components.Card, as: CardComponent

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

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

  @types [
    {"all", "All"},
    {"ally", "Ally"},
    {"event", "Event"},
    {"support", "Support"},
    {"upgrade", "Upgrade"},
    {"resource", "Resource"},
    {"player_side_scheme", "Side Scheme"}
  ]

  @aspect_keys Enum.map(@aspects, &elem(&1, 0))
  @type_keys Enum.map(@types, &elem(&1, 0))

  # The deck's own aspect chips (panel) — the five real aspects, no "all".
  @deck_aspects [
    {:aggression, "Aggression", "bg-aspect-aggression"},
    {:justice, "Justice", "bg-aspect-justice"},
    {:leadership, "Leadership", "bg-aspect-leadership"},
    {:protection, "Protection", "bg-aspect-protection"},
    {:pool, "'Pool", "bg-aspect-pool"}
  ]

  # Panel group order; hero signature cards get their own leading group.
  @type_order [:ally, :event, :support, :upgrade, :resource, :player_side_scheme]
  @type_labels %{
    ally: "Allies",
    event: "Events",
    support: "Supports",
    upgrade: "Upgrades",
    resource: "Resources",
    player_side_scheme: "Side Schemes"
  }

  # Core-set printings of the three double resources; reprints are separate
  # Card rows, so quick-add pins the canonical codes.
  @staple_codes ~w(01088 01089 01090)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    case Decks.get_deck(id,
           actor: user,
           load: [hero: [:display_name], deck_cards: [card: [:primary_side]]]
         ) do
      {:ok, %{source: :native, owner_id: owner_id} = deck} when owner_id == user.id ->
        {:ok, seed(socket, deck)}

      {:ok, deck} ->
        {:ok,
         socket
         |> put_flash(:error, "Only the owner can build this deck.")
         |> push_navigate(to: ~p"/decks/#{deck.id}")}

      {:error, _error} ->
        {:ok,
         socket
         |> put_flash(:error, "Deck not found.")
         |> push_navigate(to: ~p"/decks")}
    end
  end

  defp seed(socket, deck) do
    entries =
      Map.new(deck.deck_cards, fn dc ->
        {dc.card_id,
         %{card: dc.card, quantity: dc.quantity, ignore_deck_limit: dc.ignore_deck_limit}}
      end)

    signature_cards = Decks.signature_cards(deck.hero_id)
    signature_ids = MapSet.new(signature_cards, & &1.id)

    socket
    |> assign(:page_title, "Build · #{deck.title}")
    |> assign(:deck, deck)
    |> assign(:entries, entries)
    |> assign(:signature_cards, signature_cards)
    |> assign(:signature_ids, signature_ids)
    |> assign(:staples, load_staples())
    |> recompute_issues()
    |> assign(:panel_open?, false)
    |> assign(:confirm_delete?, false)
    |> assign(:deck_aspect_options, @deck_aspects)
    |> assign(:query, "")
    |> assign(:search_diagnostics, [])
    |> assign(:aspect, "all")
    |> assign(:type, "all")
    |> assign(:count, nil)
    |> assign(:aspect_options, @aspects)
    |> assign(:type_options, @types)
    |> assign(:offset, 0)
    |> assign(:end_of_timeline?, false)
    |> assign(:req_id, 0)
    |> assign(:loading?, true)
    |> assign(:tile_cache, %{})
    |> stream(:cards, [], dom_id: &"pool-card-#{&1.card_id}")
  end

  defp load_staples do
    @staple_codes
    |> Enum.map(fn code ->
      # primary_side rides along for Legality checks and the deck panel.
      case Sanctum.Games.get_card_by_code(code, load: [:primary_side]) do
        {:ok, card} -> card
        _missing -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # The initial load starts on the connected mount only (req_id == 0).
  @impl true
  def handle_params(_params, _uri, socket) do
    socket =
      if connected?(socket) and socket.assigns[:req_id] == 0,
        do: start_load(socket, 0, reset: true),
        else: socket

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:query, query)
      |> assign(:search_diagnostics, search_diagnostics(query))
      |> start_load(0, reset: true)

    {:noreply, socket}
  end

  def handle_event("suggest", %{"value" => value, "cursor" => cursor}, socket)
      when is_binary(value) and is_integer(cursor) do
    {:reply, Sanctum.Search.Suggest.suggest(value, cursor, Sanctum.Search.CardFields), socket}
  end

  def handle_event("suggest", _params, socket), do: {:reply, %{items: []}, socket}

  def handle_event("filter_aspect", %{"key" => key}, socket) when key in @aspect_keys do
    {:noreply, socket |> assign(:aspect, key) |> start_load(0, reset: true)}
  end

  def handle_event("filter_type", %{"key" => key}, socket) when key in @type_keys do
    {:noreply, socket |> assign(:type, key) |> start_load(0, reset: true)}
  end

  def handle_event("clear", _params, socket) do
    socket =
      socket
      |> assign(:query, "")
      |> assign(:search_diagnostics, [])
      |> assign(:aspect, "all")
      |> assign(:type, "all")
      |> start_load(0, reset: true)

    {:noreply, socket}
  end

  def handle_event("next-page", _params, socket) do
    if socket.assigns.end_of_timeline? or socket.assigns.loading? do
      {:noreply, socket}
    else
      {:noreply, start_load(socket, socket.assigns.offset + @page_size)}
    end
  end

  def handle_event("inc", %{"card-id" => card_id}, socket) do
    {:noreply, change_quantity(socket, card_id, +1)}
  end

  def handle_event("dec", %{"card-id" => card_id}, socket) do
    {:noreply, change_quantity(socket, card_id, -1)}
  end

  # Idempotent: sets each missing staple to 1x, leaves present ones alone.
  def handle_event("add_staples", _params, socket) do
    socket =
      Enum.reduce(socket.assigns.staples, socket, fn card, socket ->
        case current_qty(socket, card.id) do
          0 -> put_quantity(socket, card, 1)
          _present -> socket
        end
      end)

    {:noreply, socket}
  end

  def handle_event("toggle_panel", _params, socket) do
    {:noreply, assign(socket, :panel_open?, !socket.assigns.panel_open?)}
  end

  # Fired on blur and on Enter (form submit); both carry the new title.
  def handle_event("rename", params, socket) do
    title = params["title"] || params["value"] || ""
    deck = socket.assigns.deck

    if String.trim(title) in ["", deck.title] do
      {:noreply, socket}
    else
      updated = Decks.rename_deck!(deck, %{title: title}, actor: socket.assigns.current_user)

      {:noreply,
       socket
       |> assign(:deck, %{deck | title: updated.title})
       |> assign(:page_title, "Build · #{updated.title}")}
    end
  end

  def handle_event("toggle_deck_aspect", %{"key" => key}, socket) do
    aspect = String.to_existing_atom(key)
    deck = socket.assigns.deck

    aspects =
      if aspect in deck.aspects,
        do: List.delete(deck.aspects, aspect),
        else: deck.aspects ++ [aspect]

    updated =
      Decks.set_deck_aspects!(deck, %{aspects: aspects}, actor: socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:deck, %{deck | aspects: updated.aspects})
     |> recompute_issues()}
  end

  def handle_event("confirm_delete", _params, socket) do
    {:noreply, assign(socket, :confirm_delete?, true)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :confirm_delete?, false)}
  end

  def handle_event("delete_deck", _params, socket) do
    Decks.destroy_deck!(socket.assigns.deck, actor: socket.assigns.current_user)

    {:noreply,
     socket
     |> put_flash(:info, "Deck deleted.")
     |> push_navigate(to: ~p"/decks")}
  end

  @impl true
  def handle_async(:load_cards, {:ok, result}, socket) do
    %{req: req, offset: offset, reset?: reset?, page: page} = result

    if req == socket.assigns.req_id do
      tiles = Enum.map(page.results, &tile_view/1)

      tile_cache =
        if reset?,
          do: Map.new(tiles, &{&1.card_id, &1}),
          else: Enum.into(tiles, socket.assigns.tile_cache, &{&1.card_id, &1})

      {:noreply,
       socket
       |> assign(:offset, offset)
       |> assign(:end_of_timeline?, !page.more?)
       |> assign(:loading?, false)
       |> maybe_assign_count(reset?, page.count)
       |> assign(:tile_cache, tile_cache)
       |> stream(:cards, tiles, reset: reset?)}
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

  # -- quantity plumbing ------------------------------------------------------

  defp change_quantity(socket, card_id, delta) do
    qty = current_qty(socket, card_id)
    new_qty = max(qty + delta, 0)

    cond do
      new_qty == qty ->
        socket

      # Signature cards are locked to the hero set — the grid never offers
      # them (scope excludes :hero ownership), but guard the event anyway.
      MapSet.member?(socket.assigns.signature_ids, card_id) ->
        put_flash(socket, :error, "Hero cards are locked to the signature set.")

      delta > 0 and new_qty > max_qty(socket, card_id) ->
        socket

      true ->
        case find_card(socket, card_id) do
          nil -> socket
          card -> put_quantity(socket, card, new_qty)
        end
    end
  end

  # Persist + update entries, issues, and the visible tile. `card` must carry
  # a usable primary side (tile_view or deck_cards both guarantee it).
  defp put_quantity(socket, card, new_qty) do
    deck = socket.assigns.deck
    user = socket.assigns.current_user

    Decks.set_card_quantity(deck.id, card.id, new_qty, user)

    entries =
      if new_qty == 0 do
        Map.delete(socket.assigns.entries, card.id)
      else
        Map.update(
          socket.assigns.entries,
          card.id,
          %{card: card, quantity: new_qty, ignore_deck_limit: false},
          &%{&1 | quantity: new_qty}
        )
      end

    socket
    |> assign(:entries, entries)
    |> recompute_issues()
    |> refresh_tile(card.id, new_qty)
  end

  defp refresh_tile(socket, card_id, new_qty) do
    case socket.assigns.tile_cache[card_id] do
      nil ->
        socket

      tile ->
        tile = %{tile | qty: new_qty}

        socket
        |> assign(:tile_cache, Map.put(socket.assigns.tile_cache, card_id, tile))
        |> stream_insert(:cards, tile)
    end
  end

  defp current_qty(socket, card_id) do
    case socket.assigns.entries[card_id] do
      %{quantity: qty} -> qty
      nil -> 0
    end
  end

  defp max_qty(socket, card_id) do
    card = find_card(socket, card_id)

    cond do
      is_nil(card) -> 0
      card.unique -> 1
      true -> card.deck_limit || 1
    end
  end

  # A card either came in from the grid (tile_cache keeps the Card struct with
  # its primary side attached), the current entries, or the staples row.
  defp find_card(socket, card_id) do
    cond do
      tile = socket.assigns.tile_cache[card_id] -> tile.card
      entry = socket.assigns.entries[card_id] -> entry.card
      card = Enum.find(socket.assigns.staples, &(&1.id == card_id)) -> card
      true -> nil
    end
  end

  defp recompute_issues(socket) do
    issues =
      Legality.issues(
        Map.values(socket.assigns.entries),
        socket.assigns.deck.aspects,
        socket.assigns.signature_cards
      )

    assign(socket, :issues, issues)
  end

  defp deck_size(entries) do
    entries
    |> Map.values()
    |> Enum.reject(& &1.card.permanent)
    |> Enum.reduce(0, &(&1.quantity + &2))
  end

  # -- grid loading -----------------------------------------------------------

  defp start_load(socket, offset, opts \\ []) do
    reset? = Keyword.get(opts, :reset, false)
    req = socket.assigns.req_id + 1
    actor = socket.assigns.current_user

    filters = %{
      query: socket.assigns.query,
      aspect: socket.assigns.aspect,
      type: socket.assigns.type,
      scope: "deckbuilding"
    }

    socket
    |> assign(:req_id, req)
    |> assign(:loading?, true)
    |> start_async(:load_cards, fn ->
      page =
        Sanctum.Games.CardSide
        |> Ash.Query.for_read(:browse, filters, actor: actor)
        |> Ash.read!(page: [limit: @page_size, offset: offset, count: reset?])

      %{req: req, offset: offset, reset?: reset?, page: page}
    end)
  end

  # One row per card (scope filters to primary sides), so the side IS the
  # card's primary side; attach it for Legality and the deck panel.
  defp tile_view(side) do
    card = %{side.card | primary_side: side}
    resources = side_resources(side)

    %{
      card_id: card.id,
      card: card,
      name: side.name,
      cost: side.cost,
      type: side.type,
      aspect_key: display_aspect(side),
      resources: resources,
      image_url: side.image_url,
      unique: card.unique,
      max: if(card.unique, do: 1, else: card.deck_limit || 1),
      # qty is stamped at build time and re-stamped on every change.
      qty: 0
    }
  end

  defp display_aspect(%{ownership: :player, aspect: aspect}) when not is_nil(aspect), do: aspect
  defp display_aspect(%{ownership: :hero}), do: :hero
  defp display_aspect(%{ownership: :basic}), do: :basic
  defp display_aspect(%{aspect: aspect}) when not is_nil(aspect), do: aspect
  defp display_aspect(_side), do: :basic

  defp side_resources(side) do
    [
      energy: side.resource_energy_count,
      mental: side.resource_mental_count,
      physical: side.resource_physical_count,
      wild: side.resource_wild_count
    ]
    |> Enum.flat_map(fn {res, n} -> List.duplicate(res, n || 0) end)
  end

  # -- deck panel data --------------------------------------------------------

  # Hero signature cards lead (locked rows), then chosen cards by type.
  defp panel_groups(entries) do
    rows = entries |> Map.values() |> Enum.map(&panel_row/1)
    {hero_rows, chosen} = Enum.split_with(rows, & &1.hero?)

    typed =
      @type_order
      |> Enum.map(fn type ->
        group =
          chosen
          |> Enum.filter(&(&1.type == type))
          |> Enum.sort_by(&String.downcase(&1.name))

        {Map.fetch!(@type_labels, type), group}
      end)
      |> Kernel.++([{"Other", Enum.filter(chosen, &(&1.type not in @type_order))}])
      |> Enum.reject(fn {_label, group} -> group == [] end)

    case hero_rows do
      [] -> typed
      rows -> [{"Hero", Enum.sort_by(rows, &String.downcase(&1.name))} | typed]
    end
  end

  defp panel_row(%{card: card, quantity: qty}) do
    side = card.primary_side
    aspect_key = display_aspect(side)

    %{
      card_id: card.id,
      qty: qty,
      name: side.name,
      type: side.type,
      hero?: side.ownership == :hero,
      aspect_key: aspect_key,
      aspect_bg: CardComponent.aspect_classes(aspect_key).bg,
      pips: CardComponent.resource_pips(side_resources(side)),
      max: if(card.unique, do: 1, else: card.deck_limit || 1)
    }
  end

  defp maybe_assign_count(socket, false, _count), do: socket
  defp maybe_assign_count(socket, true, count), do: assign(socket, :count, count)

  defp search_diagnostics(query) when is_binary(query) and query != "" do
    Sanctum.Search.compile(query, Sanctum.Search.CardFields).diagnostics
  end

  defp search_diagnostics(_query), do: []

  # -- render -----------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:decks}>
      <.header>
        {@deck.title}
        <:subtitle>{@deck.hero.display_name} · building</:subtitle>
        <:actions>
          <.button navigate={~p"/decks/#{@deck.id}"} class="hidden sm:inline-flex">
            View Deck
          </.button>
        </:actions>
      </.header>

      <div class="lg:grid lg:grid-cols-[minmax(0,1fr)_400px] lg:items-start lg:gap-5">
        <!-- left: browse + grid -->
        <div class="min-w-0">
          <div class="mb-3.5">
            <form id="builder-search" phx-change="search" class="flex w-full">
              <.query_input
                id="builder-query"
                value={@query}
                name="query"
                placeholder="Search cards — try cost<=2 type:ally owned:true"
                placeholder_short="Search cards…"
                registry={Sanctum.Search.CardFields}
                diagnostics={@search_diagnostics}
                help_path={~p"/search-help" <> "#cards"}
              />
            </form>
            <div class="mt-2 flex items-center gap-2 whitespace-nowrap font-anton text-[15px] uppercase tracking-[0.05em]">
              <.icon
                :if={@loading?}
                name="hero-arrow-path"
                class="size-4 animate-spin text-base-content/45"
              />
              <span :if={@count == nil} class="text-base-content/45">Loading…</span>
              <span :if={@count != nil}>{@count} cards</span>
            </div>
          </div>

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

          <div class="mb-3 flex flex-wrap gap-1.5">
            <.filter_pill
              :for={{key, label} <- @type_options}
              active={@type == key}
              phx-click="filter_type"
              phx-value-key={key}
            >
              {label}
            </.filter_pill>
          </div>

          <!-- staples quick-add -->
          <div :if={@staples != []} class="mb-5 flex flex-wrap items-center gap-2">
            <button
              type="button"
              phx-click="add_staples"
              class="inline-flex min-h-[44px] cursor-pointer items-center gap-1.5 border-2 border-neutral bg-base-300 px-3.5 py-1.5 font-barlow-condensed text-[13px] font-bold uppercase tracking-[0.07em] text-base-content transition-colors hover:border-primary hover:text-primary sm:min-h-0 sm:px-3 sm:text-[12px]"
            >
              <.icon name="hero-bolt" class="size-3.5" /> Add Energy · Genius · Strength
            </button>
            <span class="font-barlow-condensed text-[12px] uppercase tracking-[0.06em] text-base-content/45">
              {staples_status(@staples, @entries)}
            </span>
          </div>

          <!-- first-load skeletons -->
          <.art_grid_skeleton :if={@count == nil} count={12} />

          <!-- card grid -->
          <div
            id="builder-grid"
            phx-update="stream"
            phx-viewport-bottom={!@end_of_timeline? && "next-page"}
            class={[
              "grid grid-cols-[repeat(auto-fill,minmax(140px,1fr))] items-start gap-2.5 pb-24 lg:pb-6",
              @loading? && @count != nil && "opacity-60 transition-opacity"
            ]}
          >
            <div :for={{dom_id, tile} <- @streams.cards} id={dom_id} class="relative">
              <.link navigate={~p"/cards/#{tile.card_id}"} class="block border-2 border-neutral">
                <.mc_card
                  name={tile.name}
                  cost={tile.cost}
                  type={tile.type}
                  aspect={tile.aspect_key}
                  resources={tile.resources}
                  qty={tile.qty}
                  size="md"
                  image_url={tile.image_url}
                />
              </.link>
              <.qty_stepper
                card_id={tile.card_id}
                qty={tile.qty}
                max={tile.max}
                class="absolute bottom-1.5 right-1.5 z-10"
              />
            </div>
          </div>

          <!-- empty state -->
          <.panel
            :if={@count == 0}
            class="mt-2 border-dashed !border-[#2a2a30] px-6 py-12 text-center !shadow-none"
          >
            <div class="font-bangers text-[30px] tracking-[0.02em] text-primary">
              No cards found
            </div>
            <div class="mt-1.5 font-barlow text-[14px] text-base-content/55">
              Try a different search or clear your filters.
            </div>
            <.button variant="primary" phx-click="clear" class="mt-4">Clear filters</.button>
          </.panel>
        </div>

        <!-- right: desktop deck panel -->
        <div
          id="deck-panel-desktop"
          class="sticky top-4 hidden max-h-[calc(100dvh-2rem)] overflow-y-auto border-2 border-neutral bg-base-200 shadow-comic lg:block"
        >
          <.deck_panel
            id="desktop"
            deck={@deck}
            entries={@entries}
            issues={@issues}
            deck_aspect_options={@deck_aspect_options}
            confirm_delete?={@confirm_delete?}
          />
        </div>
      </div>

      <!-- mobile slide-up deck pane (never a modal: the page stays live behind it) -->
      <div
        id="deck-panel-mobile"
        class={[
          "fixed inset-x-0 bottom-0 z-30 max-h-[75dvh] overflow-y-auto border-t-2 border-neutral bg-base-100",
          "transition-transform duration-200 lg:hidden",
          (@panel_open? && "translate-y-0") || "translate-y-full"
        ]}
      >
        <button
          type="button"
          phx-click="toggle_panel"
          class="flex w-full cursor-pointer items-center justify-center gap-2 py-2 text-base-content/50"
          title="Close deck panel"
        >
          <span class="h-1 w-10 rounded-full bg-base-content/25"></span>
          <.icon name="hero-chevron-down" class="size-4" />
        </button>
        <.deck_panel
          id="mobile"
          deck={@deck}
          entries={@entries}
          issues={@issues}
          deck_aspect_options={@deck_aspect_options}
          confirm_delete?={@confirm_delete?}
        />
      </div>

      <!-- persistent mobile deck bar -->
      <div class="fixed inset-x-0 bottom-0 z-20 border-t-2 border-neutral bg-base-100/95 px-4 py-2.5 backdrop-blur lg:hidden">
        <button
          type="button"
          phx-click="toggle_panel"
          class="flex w-full cursor-pointer items-center justify-between gap-3"
        >
          <span class="font-anton text-[15px] uppercase tracking-[0.05em]">
            <span class={deck_size_class(deck_size(@entries))}>{deck_size(@entries)}</span>
            <span class="text-base-content/45">/ 40–50 cards</span>
          </span>
          <span
            :if={@issues != []}
            class="inline-flex items-center gap-1 font-barlow-condensed text-[13px] font-bold uppercase tracking-[0.07em] text-warning"
          >
            <.icon name="hero-exclamation-triangle" class="size-3.5" /> {length(@issues)}
          </span>
          <span class="inline-flex items-center gap-1 font-barlow-condensed text-[13px] font-bold uppercase tracking-[0.08em] text-base-content/70">
            Deck <.icon name="hero-chevron-up" class="size-3.5" />
          </span>
        </button>
      </div>
    </Layouts.app>
    """
  end

  # Shared by the desktop side column and the mobile slide-up pane; `id`
  # disambiguates the two instances' form/input DOM ids.
  attr :id, :string, required: true
  attr :deck, :map, required: true
  attr :entries, :map, required: true
  attr :issues, :list, required: true
  attr :deck_aspect_options, :list, required: true
  attr :confirm_delete?, :boolean, required: true

  defp deck_panel(assigns) do
    assigns = assign(assigns, :groups, panel_groups(assigns.entries))
    assigns = assign(assigns, :size, deck_size(assigns.entries))

    ~H"""
    <div class="flex flex-col gap-4 p-4">
      <!-- title + count -->
      <div>
        <form id={"rename-#{@id}"} phx-submit="rename" class="flex items-center gap-2">
          <input
            type="text"
            name="title"
            value={@deck.title}
            phx-blur="rename"
            autocomplete="off"
            class="min-h-[44px] w-full border-[2.5px] border-transparent bg-transparent px-1 font-anton text-[18px] uppercase tracking-[0.04em] text-base-content outline-none focus:border-line focus:bg-black sm:min-h-0"
          />
        </form>
        <div class="mt-1 flex items-center justify-between px-1">
          <span class="font-anton text-[14px] uppercase tracking-[0.05em]">
            <span class={deck_size_class(@size)}>{@size}</span>
            <span class="text-base-content/45">/ 40–50 cards</span>
          </span>
          <.link
            navigate={~p"/decks/#{@deck.id}"}
            class="font-barlow-condensed text-[13px] font-bold uppercase tracking-[0.08em] text-base-content/60 hover:text-base-content"
          >
            View deck →
          </.link>
        </div>
      </div>

      <!-- deck aspects -->
      <div class="flex flex-wrap gap-1.5">
        <.filter_pill
          :for={{key, label, dot_class} <- @deck_aspect_options}
          active={key in @deck.aspects}
          dot_class={dot_class}
          type="button"
          phx-click="toggle_deck_aspect"
          phx-value-key={key}
        >
          {label}
        </.filter_pill>
      </div>

      <!-- advisory issues -->
      <div
        :if={@issues != []}
        class="border-2 border-warning/40 bg-warning/5 px-3 py-2.5"
      >
        <div class="mb-1.5 flex items-center gap-1.5 font-barlow-condensed text-[13px] font-bold uppercase tracking-[0.08em] text-warning">
          <.icon name="hero-exclamation-triangle" class="size-3.5" /> Deck issues (advisory)
        </div>
        <ul class="flex flex-col gap-1">
          <li
            :for={issue <- @issues}
            class={[
              "font-barlow-condensed text-[13px]",
              (issue.severity == :error && "text-error/90") || "text-base-content/70"
            ]}
          >
            {issue.message}
          </li>
        </ul>
      </div>

      <!-- grouped card list -->
      <div :for={{label, rows} <- @groups}>
        <div class="mb-1 flex items-baseline justify-between border-b-2 border-neutral pb-1">
          <span class="font-anton text-[13px] uppercase tracking-[0.08em] text-base-content/70">
            {label}
          </span>
          <span class="font-ibm-mono text-[11px] text-base-content/45">
            {rows |> Enum.map(& &1.qty) |> Enum.sum()}
          </span>
        </div>
        <div class="divide-y divide-neutral/40">
          <div :for={row <- rows} class="flex min-h-[40px] items-center gap-2 px-1 py-1">
            <span class="w-6 flex-none font-ibm-mono text-[11px] text-base-content/50">
              {row.qty}×
            </span>
            <.icon
              :if={row.hero?}
              name="hero-user-solid"
              class="size-3 flex-none text-aspect-hero"
            />
            <span :if={!row.hero?} class={["size-2.5 flex-none", row.aspect_bg]}></span>
            <.link
              navigate={~p"/cards/#{row.card_id}"}
              class="truncate font-barlow-condensed text-[14px] font-semibold text-base-content/85 hover:text-base-content"
            >
              {row.name}
            </.link>
            <span :if={row.pips != []} class="ml-auto flex flex-none items-center gap-1">
              <span
                :for={{color_class, glyph} <- row.pips}
                class={["font-champions text-[13px] leading-none", color_class]}
              >
                {glyph}
              </span>
            </span>
            <span :if={row.hero?} class="ml-auto flex-none" title="Locked to the hero set">
              <.icon name="hero-lock-closed" class="size-3 text-base-content/35" />
            </span>
            <span
              :if={!row.hero?}
              class={["flex flex-none items-center gap-0.5", row.pips == [] && "ml-auto"]}
            >
              <button
                type="button"
                phx-click="dec"
                phx-value-card-id={row.card_id}
                title="Remove a copy"
                class="flex size-8 cursor-pointer items-center justify-center text-base-content/50 transition-colors hover:text-error sm:size-6"
              >
                <.icon name="hero-minus" class="size-3.5" />
              </button>
              <button
                type="button"
                phx-click="inc"
                phx-value-card-id={row.card_id}
                disabled={row.qty >= row.max}
                title={(row.qty >= row.max && "At this card's limit") || "Add a copy"}
                class={[
                  "flex size-8 cursor-pointer items-center justify-center transition-colors sm:size-6",
                  (row.qty >= row.max && "cursor-default text-base-content/20") ||
                    "text-base-content/50 hover:text-success"
                ]}
              >
                <.icon name="hero-plus" class="size-3.5" />
              </button>
            </span>
          </div>
        </div>
      </div>

      <p
        :if={@groups == []}
        class="font-barlow-condensed text-[14px] text-base-content/50"
      >
        No cards yet — tap + on a card to add it.
      </p>

      <!-- inline delete (two-step, no modal) -->
      <div class="mt-2 border-t-2 border-neutral pt-3">
        <button
          :if={!@confirm_delete?}
          type="button"
          phx-click="confirm_delete"
          class="font-barlow-condensed text-[13px] font-bold uppercase tracking-[0.08em] text-base-content/45 transition-colors hover:text-error"
        >
          Delete deck
        </button>
        <div :if={@confirm_delete?} class="flex items-center gap-3">
          <span class="font-barlow-condensed text-[13px] font-bold uppercase tracking-[0.08em] text-error">
            Really delete?
          </span>
          <.button phx-click="delete_deck" class="!min-h-0 !border-error !px-3 !py-1 !text-error">
            Delete
          </.button>
          <.button phx-click="cancel_delete" class="!min-h-0 !px-3 !py-1">
            Cancel
          </.button>
        </div>
      </div>
    </div>
    """
  end

  defp deck_size_class(size) when size >= 40 and size <= 50, do: "text-success"
  defp deck_size_class(_size), do: "text-base-content"

  defp staples_status(staples, entries) do
    have = Enum.count(staples, &match?(%{quantity: q} when q > 0, entries[&1.id]))

    case have do
      0 -> "one tap, 1x each"
      3 -> "all in deck"
      n -> "#{n} of 3 in deck"
    end
  end
end
