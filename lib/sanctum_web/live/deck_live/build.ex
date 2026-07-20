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
      case Sanctum.Games.get_card_by_code(code) do
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

    resources =
      [
        energy: side.resource_energy_count,
        mental: side.resource_mental_count,
        physical: side.resource_physical_count,
        wild: side.resource_wild_count
      ]
      |> Enum.flat_map(fn {res, n} -> List.duplicate(res, n || 0) end)

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
  defp display_aspect(%{ownership: :basic}), do: :basic
  defp display_aspect(%{aspect: aspect}) when not is_nil(aspect), do: aspect
  defp display_aspect(_side), do: :basic

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
        <div class="font-bangers text-[30px] tracking-[0.02em] text-primary">No cards found</div>
        <div class="mt-1.5 font-barlow text-[14px] text-base-content/55">
          Try a different search or clear your filters.
        </div>
        <.button variant="primary" phx-click="clear" class="mt-4">Clear filters</.button>
      </.panel>

      <!-- persistent deck bar (panel arrives in the next phase) -->
      <div class="fixed inset-x-0 bottom-0 z-20 border-t-2 border-neutral bg-base-100/95 px-4 py-2.5 backdrop-blur lg:hidden">
        <div class="flex items-center justify-between gap-3">
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
          <.button navigate={~p"/decks/#{@deck.id}"} class="!min-h-0 !px-3 !py-1.5">
            View
          </.button>
        </div>
      </div>
    </Layouts.app>
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
