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

  import SanctumWeb.Components.CardPreview
  import SanctumWeb.Components.DeckCards
  import SanctumWeb.Components.FilterSheet
  import SanctumWeb.Components.QueryInput

  alias Sanctum.Search.FormSync

  alias Sanctum.Decks
  alias Sanctum.Decks.Legality
  alias Sanctum.Decks.Writeup
  alias SanctumWeb.Components.DeckCards

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  @page_size 24

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
    |> assign(:hero_gradient, hero_gradient(deck.hero))
    |> assign(:card_view, "images")
    |> assign(:entries, entries)
    |> assign(:signature_cards, signature_cards)
    |> assign(:signature_ids, signature_ids)
    |> assign(:staples, load_staples())
    |> recompute_issues()
    |> assign_card_preview()
    |> assign(:panel_open?, false)
    |> assign(:confirm_delete?, false)
    |> assign(:tab, "cards")
    |> assign(:description_draft, deck.description_md || "")
    |> assign(:description_mode, "write")
    |> assign(:description_preview, nil)
    |> assign(:description_dirty?, false)
    |> assign(:picker, nil)
    |> assign(:picker_query, "")
    |> assign(:picker_results, [])
    |> assign(:query, "")
    |> assign(:search_diagnostics, [])
    |> assign(:filters_open?, false)
    |> assign(:filter_count, 0)
    |> assign(:count, nil)
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
    {:noreply, apply_query(socket, query)}
  end

  def handle_event("suggest", %{"value" => value, "cursor" => cursor}, socket)
      when is_binary(value) and is_integer(cursor) do
    {:reply, Sanctum.Search.Suggest.suggest(value, cursor, Sanctum.Search.CardFields), socket}
  end

  def handle_event("suggest", _params, socket), do: {:reply, %{items: []}, socket}

  # Card-mention autocomplete for the description editor: `#query` in the
  # textarea (DescriptionEditor hook, same trigger as MarvelCDB's editor)
  # searches every catalog face — writeups reference villains and encounter
  # cards, not just the buildable pool — and the picker inserts the
  # `[Name](/card/CODE)` markdown that Writeup.render already resolves.
  # (The hook's `$` icon picker filters locally from data-icons; no event.)
  def handle_event("card_mention", %{"q" => q}, socket) when is_binary(q) do
    {:reply, %{items: mention_items(q, socket.assigns.current_user)}, socket}
  end

  def handle_event("card_mention", _params, socket), do: {:reply, %{items: []}, socket}

  # The toolbar's Card/Icon buttons open a search-and-pick overlay (centered
  # dialog on desktop, bottom sheet on mobile). The hook saves the caret
  # before pushing this event; picking pushes "writeup:insert" back so the
  # hook splices the text in at that spot.
  def handle_event("open_picker", %{"kind" => kind}, socket) when kind in ["card", "icon"] do
    {:noreply,
     socket
     |> assign(:picker, kind)
     |> assign(:picker_query, "")
     |> assign(:picker_results, if(kind == "icon", do: filter_icons(""), else: []))}
  end

  def handle_event("close_picker", _params, socket) do
    {:noreply, assign(socket, :picker, nil)}
  end

  def handle_event("picker_search", %{"q" => q}, socket) when is_binary(q) do
    results =
      case socket.assigns.picker do
        "card" -> mention_items(q, socket.assigns.current_user, 12)
        "icon" -> filter_icons(q)
        nil -> []
      end

    {:noreply, socket |> assign(:picker_query, q) |> assign(:picker_results, results)}
  end

  # Enter in the picker's search box takes the top result.
  def handle_event("picker_submit", _params, socket) do
    case socket.assigns.picker_results do
      [top | _rest] -> {:noreply, insert_pick(socket, top)}
      [] -> {:noreply, socket}
    end
  end

  def handle_event("pick", %{"index" => index}, socket) do
    case Enum.at(socket.assigns.picker_results, String.to_integer(index)) do
      nil -> {:noreply, socket}
      item -> {:noreply, insert_pick(socket, item)}
    end
  end

  # The filter sheet and the mobile deck pane are both z-40/z-50 overlays —
  # opening one closes the other.
  def handle_event("toggle_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:filters_open?, !socket.assigns.filters_open?)
     |> assign(:panel_open?, false)}
  end

  # A filter-sheet change: splice the submitted controls back into the query
  # string. Unlike the browse pages, builder filter state lives in assigns
  # (no URL round-trip), so this re-loads directly.
  def handle_event("filters_change", params, socket) do
    fields = FormSync.fields_from_params(params, Sanctum.Search.CardFields)
    query = FormSync.update(socket.assigns.query, Sanctum.Search.CardFields, fields)

    {:noreply, apply_query(socket, query)}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, apply_query(socket, "")}
  end

  def handle_event("next-page", _params, socket) do
    if socket.assigns.end_of_timeline? or socket.assigns.loading? do
      {:noreply, socket}
    else
      {:noreply, start_load(socket, socket.assigns.offset + @page_size)}
    end
  end

  # Pushed by the CardLinkPreview hook when a decklist tile/row is hovered.
  def handle_event("preview_card", %{"id" => id}, socket) do
    handle_preview_event(id, socket)
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
    {:noreply,
     socket
     |> assign(:panel_open?, !socket.assigns.panel_open?)
     |> assign(:filters_open?, false)}
  end

  def handle_event("set_tab", %{"key" => tab}, socket) when tab in ["cards", "description"] do
    {:noreply, assign(socket, :tab, tab)}
  end

  # Shared with the deck page: same events, same localStorage key, so the
  # images/list preference follows the user between viewing and building.
  def handle_event(event, params, socket)
      when event in ["set_card_view", "restore_card_view"] do
    {:noreply, DeckCards.handle_card_view_event(event, params, socket)}
  end

  def handle_event("description_change", %{"description" => draft}, socket) do
    {:noreply,
     socket
     |> assign(:description_draft, draft)
     |> assign(:description_dirty?, draft != (socket.assigns.deck.description_md || ""))}
  end

  # Preview renders on demand (not per keystroke) — Writeup.render resolves
  # card links against the catalog, so it costs reads.
  def handle_event("set_description_mode", %{"key" => mode}, socket)
      when mode in ["write", "preview"] do
    socket =
      if mode == "preview" do
        assign(socket, :description_preview, Writeup.render(socket.assigns.description_draft))
      else
        socket
      end

    {:noreply, assign(socket, :description_mode, mode)}
  end

  def handle_event("save_description", _params, socket) do
    %{deck: deck, description_draft: draft, current_user: user} = socket.assigns

    updated = Decks.set_deck_description!(deck, %{description_md: draft}, actor: user)

    {:noreply,
     socket
     |> assign(:deck, %{deck | description_md: updated.description_md})
     |> assign(:description_dirty?, false)}
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
      # Stamp each tile with the deck's current quantity so cards already in
      # the deck arrive badged (fresh mounts, filter changes, later pages).
      entries = socket.assigns.entries

      tiles =
        Enum.map(page.results, fn side ->
          tile = tile_view(side)
          %{tile | qty: current_entry_qty(entries, tile.card_id)}
        end)

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

  defp current_qty(socket, card_id), do: current_entry_qty(socket.assigns.entries, card_id)

  defp current_entry_qty(entries, card_id) do
    case entries[card_id] do
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

    filters = %{query: socket.assigns.query, scope: "deckbuilding"}

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
      cost: display_value(side.cost),
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

  # -- deck panel data --------------------------------------------------------

  # Grouped exactly like the deck page's "In This Deck" section: by card type
  # in canonical order, hero signature cards folded into their type (marked
  # with a lock), names sorted within each group.
  defp panel_groups(entries, hero_gradient) do
    entries
    |> Map.values()
    |> Enum.map(&DeckCards.card_view(&1, hero_gradient))
    |> DeckCards.group_by_type()
  end

  defp maybe_assign_count(socket, false, _count), do: socket
  defp maybe_assign_count(socket, true, count), do: assign(socket, :count, count)

  # Shared landing point for every query mutation (typing, sheet changes,
  # clear): assigns + diagnostics + badge count + reload. A no-op change
  # (e.g. a half-typed typeahead value FormSync declined to commit) skips
  # the reload.
  defp apply_query(socket, query) do
    if query == socket.assigns.query do
      socket
    else
      socket
      |> assign(:query, query)
      |> assign(:search_diagnostics, search_diagnostics(query))
      |> assign(:filter_count, FormSync.active_count(query, Sanctum.Search.CardFields))
      |> start_load(0, reset: true)
    end
  end

  defp search_diagnostics(query) when is_binary(query) and query != "" do
    Sanctum.Search.compile(query, Sanctum.Search.CardFields).diagnostics
  end

  defp search_diagnostics(_query), do: []

  # Most-used first: the four resources, then the encounter/game symbols.
  # Tokens CardText knows but this list doesn't sort after them, so a new
  # glyph in the font shows up in the picker without touching this module.
  @icon_order ~w(energy mental physical wild boost acceleration amplify crisis
                 hazard star unique per_hero per_group cost)
              |> Enum.with_index()
              |> Map.new()

  # The `$` icon picker's choices (DescriptionEditor hook, data-icons).
  defp mention_icons do
    Sanctum.CardText.icons()
    |> Enum.sort_by(fn {token, _} -> {Map.get(@icon_order, token, 99), token} end)
    |> Enum.map(fn {token, {glyph, color}} ->
      %{token: token, glyph: glyph, color: color, label: Phoenix.Naming.humanize(token)}
    end)
  end

  defp filter_icons(q) do
    q = q |> String.trim() |> String.downcase()

    Enum.filter(mention_icons(), fn icon ->
      String.contains?(icon.token, q) or String.contains?(String.downcase(icon.label), q)
    end)
  end

  defp mention_items(q, actor, limit \\ 8) do
    if String.trim(q) == "" do
      []
    else
      page =
        Sanctum.Games.CardSide
        |> Ash.Query.for_read(:browse, %{query: q}, actor: actor)
        |> Ash.read!(page: [limit: limit])

      Enum.map(page.results, fn side ->
        %{
          name: side.name,
          # Some catalog entries repeat the name as subname; drop the echo.
          subname: side.subname != side.name && side.subname,
          type: side.type && Phoenix.Naming.humanize(side.type),
          code: side.card.base_code,
          image_url: side.image_url
        }
      end)
    end
  end

  defp insert_pick(socket, %{token: token}), do: push_writeup_insert(socket, "[#{token}]")

  defp insert_pick(socket, %{name: name, code: code}),
    do: push_writeup_insert(socket, "[#{name}](/card/#{code})")

  defp push_writeup_insert(socket, text) do
    socket
    |> push_event("writeup:insert", %{text: text})
    |> assign(:picker, nil)
  end

  # -- render -----------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:decks}>
      <.card_view_pref id="builder-card-view-pref" />
      <.haptics />
      <.header>
        {@deck.title}
        <:actions>
          <div :if={!@confirm_delete?} class="flex items-center gap-2.5">
            <.button phx-click="confirm_delete" class="!text-error">
              <.icon name="hero-trash" /> Delete
            </.button>
            <.button navigate={~p"/decks/#{@deck.id}"} class="hidden sm:inline-flex">
              View Deck
            </.button>
          </div>
          <!-- two-step confirm, inline (no modal) -->
          <div :if={@confirm_delete?} class="flex items-center gap-2.5">
            <span class="font-barlow-condensed text-[13px] font-bold uppercase tracking-[0.08em] text-error">
              Really delete?
            </span>
            <.button phx-click="delete_deck" class="!text-error">
              Delete
            </.button>
            <.button phx-click="cancel_delete">Cancel</.button>
          </div>
        </:actions>
      </.header>

      <!-- build/description tabs -->
      <div class="mb-5 flex border-b-2 border-neutral">
        <button
          :for={{key, label} <- [{"cards", "Cards"}, {"description", "Description"}]}
          type="button"
          phx-click="set_tab"
          phx-value-key={key}
          class={[
            "-mb-[2px] cursor-pointer border-b-[3px] px-4 py-2.5 font-anton text-[14px] uppercase tracking-[0.06em] transition-colors",
            (@tab == key && "border-primary text-primary") ||
              "border-transparent text-base-content/55 hover:text-base-content"
          ]}
        >
          {label}
          <span :if={key == "description" && @description_dirty?} class="text-warning">•</span>
        </button>
      </div>

      <!-- The cards tab hides via CSS (never unmounts): the grid is a LiveView
           stream, and stream items aren't resent if the container re-enters
           the DOM. The lg:grid classes only apply on the cards tab — a plain
           `hidden` loses to responsive display utilities. -->
      <div class={[
        (@tab == "cards" && "lg:grid lg:grid-cols-[minmax(0,1fr)_400px] lg:items-start lg:gap-5") ||
          "hidden"
      ]}>
        <!-- left: browse + grid -->
        <div class="min-w-0">
          <div class="mb-3">
            <div class="flex w-full flex-col gap-2 sm:flex-row sm:items-start">
              <form id="builder-search" phx-change="search" class="flex w-full sm:min-w-0 sm:flex-1">
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
              <span :if={@count != nil}>{@count} cards</span>
            </div>
          </div>

          <.filter_sheet
            id="builder-filters"
            open?={@filters_open?}
            query={@query}
            registry={Sanctum.Search.CardFields}
            count={@count}
          />

          <!-- staples quick-add -->
          <div :if={@staples != []} class="mb-5 flex flex-wrap items-center gap-2">
            <button
              type="button"
              data-haptic
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
              "grid grid-cols-[repeat(auto-fill,minmax(140px,1fr))] items-start gap-2.5 pb-32 lg:pb-6",
              @loading? && @count != nil && "opacity-60 transition-opacity"
            ]}
          >
            <div :for={{dom_id, tile} <- @streams.cards} id={dom_id} class="relative aspect-[63/88]">
              <.link
                navigate={~p"/cards/#{tile.card_id}"}
                class="block h-full border-2 border-neutral"
              >
                <.mc_card
                  name={tile.name}
                  type={tile.type}
                  aspect={tile.aspect_key}
                  resources={tile.resources}
                  qty={tile.qty}
                  size="md"
                  image_url={tile.image_url}
                  show_cost={false}
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
            card_view={@card_view}
            hero_gradient={@hero_gradient}
          />
        </div>
      </div>

      <!-- description editor tab -->
      <div :if={@tab == "description"} class="mx-auto max-w-3xl">
        <div class="mb-3 flex items-center justify-between gap-3">
          <div class="flex gap-1.5">
            <.filter_pill
              :for={{key, label} <- [{"write", "Write"}, {"preview", "Preview"}]}
              active={@description_mode == key}
              type="button"
              phx-click="set_description_mode"
              phx-value-key={key}
            >
              {label}
            </.filter_pill>
          </div>
          <.button
            variant="primary"
            phx-click="save_description"
            disabled={!@description_dirty?}
            class={!@description_dirty? && "opacity-40"}
          >
            {(@description_dirty? && "Save") || "Saved"}
          </.button>
        </div>

        <form
          :if={@description_mode == "write"}
          id="description-form"
          phx-change="description_change"
        >
          <div
            id="description-editor"
            phx-hook="DescriptionEditor"
            data-icons={Jason.encode!(mention_icons())}
            class="relative"
          >
            <div class="flex flex-wrap items-center gap-0.5 border-[2.5px] border-b-0 border-line bg-base-200 px-1.5 py-1">
              <.md_tool cmd="bold" title="Bold"><span class="font-bold">B</span></.md_tool>
              <.md_tool cmd="italic" title="Italic"><span class="italic">I</span></.md_tool>
              <.md_tool cmd="heading" title="Heading">H</.md_tool>
              <.md_tool cmd="ul" title="Bulleted list">
                <.icon name="hero-list-bullet" class="size-4" />
              </.md_tool>
              <.md_tool cmd="quote" title="Quote">❝</.md_tool>
              <.md_tool cmd="link" title="Link">
                <.icon name="hero-link" class="size-4" />
              </.md_tool>
              <span class="mx-1 h-5 w-px bg-line" aria-hidden="true"></span>
              <.md_tool cmd="card" title="Link a card (or type #cardname)">
                <span class="font-bold">#</span>&nbsp;Card
              </.md_tool>
              <.md_tool cmd="icon" title="Insert a game icon (or type $icon)">
                <span class="font-bold">$</span>&nbsp;Icon
              </.md_tool>
            </div>
            <textarea
              name="description"
              phx-debounce="300"
              placeholder="Write up your deck — how it plays, key combos, mulligan advice… Markdown supported; type #cardname to link a card, $icon for symbols."
              class="block min-h-[55vh] w-full border-[2.5px] border-line bg-black px-3.5 py-3 font-ibm-mono text-[13px] leading-relaxed text-base-content outline-none focus:border-primary"
            >{@description_draft}</textarea>
            <div
              data-mention-listbox
              phx-update="ignore"
              id="description-mention-listbox"
              role="listbox"
              class="absolute z-30 hidden max-h-80 w-80 max-w-full overflow-y-auto border-2 border-neutral bg-base-200 shadow-comic"
            >
            </div>
          </div>
        </form>

        <.panel :if={@description_mode == "preview"} class="min-w-0 p-5">
          <div :if={@description_preview} class="space-y-4">
            <div :for={seg <- @description_preview}>
              <div :if={seg.kind == :inline} class="deck-writeup">{seg.html}</div>
              <iframe
                :if={seg.kind == :rich}
                title="Deck writeup preview"
                sandbox=""
                referrerpolicy="no-referrer"
                loading="lazy"
                class="deck-writeup-frame"
                srcdoc={seg.srcdoc}
              ></iframe>
            </div>
          </div>
          <div :if={!@description_preview} class="font-barlow text-[14px] italic text-base-content/45">
            Nothing to preview yet.
          </div>
        </.panel>

        <%!-- Card/icon picker: bottom sheet on mobile, centered dialog on
             sm+ (the global search overlay's presentation). Picking pushes
             "writeup:insert" to the DescriptionEditor hook, which splices
             the text at the caret position saved when the picker opened. --%>
        <div
          :if={@picker}
          id="writeup-picker"
          phx-hook=".PickerNav"
          phx-window-keydown="close_picker"
          phx-key="escape"
          class="fixed inset-0 z-50"
        >
          <script :type={Phoenix.LiveView.ColocatedHook} name=".PickerNav">
            // Arrow-key navigation for the picker overlay: the search input
            // keeps focus while ArrowUp/Down move a highlight over the result
            // rows and Enter clicks the active one (its phx-click="pick" does
            // the rest). Results re-render on every search patch, and patches
            // wipe client-added classes, so updated() re-derives the highlight
            // — resetting to the first row of each fresh result set.
            export default {
              mounted() {
                this.input = this.el.querySelector("input[name='q']")
                this.active = -1

                this.onKey = (e) => {
                  const rows = this.rows()
                  if (rows.length === 0) return

                  switch (e.key) {
                    case "ArrowDown":
                      e.preventDefault()
                      this.setActive(rows, (this.active + 1) % rows.length)
                      break
                    case "ArrowUp":
                      e.preventDefault()
                      this.setActive(rows, (this.active - 1 + rows.length) % rows.length)
                      break
                    case "Enter":
                      if (this.active >= 0 && rows[this.active]) {
                        e.preventDefault()
                        rows[this.active].click()
                      }
                      break
                  }
                }
                this.input.addEventListener("keydown", this.onKey)

                this.onMove = (e) => {
                  const row = e.target.closest("[phx-click='pick']")
                  if (!row) return
                  const rows = this.rows()
                  this.setActive(rows, rows.indexOf(row))
                }
                this.el.addEventListener("mousemove", this.onMove)

                this.updated()
              },

              updated() {
                const rows = this.rows()
                this.setActive(rows, rows.length > 0 ? 0 : -1)
              },

              rows() {
                return [...this.el.querySelectorAll("[phx-click='pick']")]
              },

              setActive(rows, i) {
                this.active = i
                rows.forEach((row, j) => row.classList.toggle("picker-active", j === i))
                if (i >= 0) rows[i]?.scrollIntoView({block: "nearest"})
              },
            }
          </script>
          <div class="absolute inset-0 bg-black/60" phx-click="close_picker" aria-hidden="true"></div>
          <div class="absolute inset-x-0 bottom-0 max-h-[85dvh] overflow-hidden border-t-[3px] border-neutral bg-base-100 p-3 sm:inset-x-auto sm:bottom-auto sm:left-1/2 sm:top-[12vh] sm:w-[min(92vw,560px)] sm:-translate-x-1/2 sm:border-2 sm:shadow-comic-lg">
            <div class="mb-2.5 flex items-center justify-between gap-3">
              <span class="font-anton text-[15px] uppercase tracking-[0.05em]">
                {(@picker == "card" && "Link a Card") || "Insert an Icon"}
              </span>
              <button
                type="button"
                phx-click="close_picker"
                aria-label="Close"
                class="flex size-8 cursor-pointer items-center justify-center text-base-content/50 hover:text-base-content"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>
            <form id="writeup-picker-form" phx-change="picker_search" phx-submit="picker_submit">
              <input
                type="text"
                name="q"
                value={@picker_query}
                placeholder={(@picker == "card" && "Search cards…") || "Filter icons…"}
                phx-debounce="150"
                phx-mounted={JS.focus()}
                autocomplete="off"
                class="w-full border-[2.5px] border-line bg-black px-3.5 py-2.5 font-barlow text-base text-base-content outline-none placeholder:text-base-content/35 focus:border-primary sm:text-[15px]"
              />
            </form>
            <div class="mt-3 max-h-[calc(85dvh-9rem)] overflow-y-auto overscroll-contain pb-[max(env(safe-area-inset-bottom),0.5rem)] sm:max-h-[55vh] sm:pb-0">
              <div :if={@picker == "card"} class="divide-y divide-neutral/40">
                <button
                  :for={{item, i} <- Enum.with_index(@picker_results)}
                  type="button"
                  data-haptic
                  phx-click="pick"
                  phx-value-index={i}
                  class="flex min-h-[52px] w-full cursor-pointer items-center gap-3 px-2 py-1.5 text-left transition-colors hover:bg-base-300"
                >
                  <img
                    :if={item.image_url}
                    src={item.image_url}
                    loading="lazy"
                    alt=""
                    class="aspect-[63/88] w-9 flex-none border border-line object-cover"
                  />
                  <div
                    :if={!item.image_url}
                    class="aspect-[63/88] w-9 flex-none border border-line bg-base-300"
                  >
                  </div>
                  <div class="min-w-0">
                    <div class="truncate font-barlow-condensed text-[15px] font-semibold">
                      {item.name}
                    </div>
                    <div class="truncate font-barlow-condensed text-[13px] text-base-content/55">
                      {[item.subname, item.type] |> Enum.filter(& &1) |> Enum.join(" · ")}
                    </div>
                  </div>
                </button>
              </div>
              <div :if={@picker == "icon"} class="grid grid-cols-3 gap-1.5 sm:grid-cols-4">
                <button
                  :for={{icon, i} <- Enum.with_index(@picker_results)}
                  type="button"
                  data-haptic
                  phx-click="pick"
                  phx-value-index={i}
                  class="flex min-h-[64px] cursor-pointer flex-col items-center justify-center gap-1.5 border-2 border-neutral bg-base-200 px-2 py-2 transition-colors hover:border-primary"
                >
                  <span class={["font-champions text-[22px] leading-none", icon.color]}>
                    {icon.glyph}
                  </span>
                  <span class="font-barlow-condensed text-[12px] font-bold uppercase tracking-[0.06em] text-base-content/70">
                    {icon.label}
                  </span>
                </button>
              </div>
              <div
                :if={@picker_results == []}
                class="px-2 py-6 text-center font-barlow text-[14px] italic text-base-content/45"
              >
                {(@picker == "card" && @picker_query == "" && "Search the card catalog…") ||
                  "No matches."}
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- scrim behind the open pane; tapping it closes -->
      <div
        :if={@tab == "cards" && @panel_open?}
        phx-click="toggle_panel"
        aria-hidden="true"
        class="fixed inset-0 z-40 bg-black/60 lg:hidden"
      >
      </div>

      <!-- mobile slide-up deck pane (never a modal: the page stays live behind it) -->
      <div
        id="deck-panel-mobile"
        phx-hook="PaneDrag"
        data-dismiss-event="toggle_panel"
        class={[
          "fixed inset-x-0 bottom-0 z-50 max-h-[75dvh] overflow-y-auto border-t-2 border-neutral bg-base-100",
          "transition-transform duration-200 lg:hidden",
          (@tab == "cards" && @panel_open? && "translate-y-0") || "translate-y-full"
        ]}
      >
        <button
          type="button"
          data-drag-handle
          data-haptic
          class="flex w-full cursor-grab touch-none items-center justify-center gap-2 py-3 text-base-content/50"
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
          card_view={@card_view}
          hero_gradient={@hero_gradient}
        />
      </div>

      <!-- persistent mobile deck bar (cards tab only — the editor needs the space) -->
      <div
        :if={@tab == "cards"}
        class="fixed inset-x-0 bottom-0 z-20 border-t-[3px] border-neutral bg-base-200 px-4 py-3 shadow-[0_-6px_18px_rgba(0,0,0,.65)] lg:hidden"
      >
        <button
          type="button"
          data-haptic
          phx-click="toggle_panel"
          class="flex min-h-[48px] w-full cursor-pointer items-center justify-between gap-3"
        >
          <span class="font-anton text-[19px] uppercase tracking-[0.05em]">
            <span class={deck_size_class(deck_size(@entries))}>{deck_size(@entries)}</span>
            <span class="text-base-content/45">/ 40–50 cards</span>
          </span>
          <span
            :if={@issues != []}
            class="inline-flex items-center gap-1 font-barlow-condensed text-[15px] font-bold uppercase tracking-[0.07em] text-warning"
          >
            <.icon name="hero-exclamation-triangle" class="size-4" /> {length(@issues)}
          </span>
          <span class="inline-flex items-center gap-1.5 border-2 border-neutral bg-primary px-3.5 py-2 font-barlow-condensed text-[14px] font-bold uppercase tracking-[0.08em] text-primary-content shadow-comic-sm">
            Deck <.icon name="hero-chevron-up" class="size-4" />
          </span>
        </button>
      </div>

      <.card_preview_popover side={@card_preview} />
    </Layouts.app>
    """
  end

  # Shared by the desktop side column and the mobile slide-up pane; `id`
  # disambiguates the two instances' form/input DOM ids.
  attr :id, :string, required: true
  attr :deck, :map, required: true
  attr :entries, :map, required: true
  attr :issues, :list, required: true
  attr :card_view, :string, required: true
  attr :hero_gradient, :any, required: true

  defp deck_panel(assigns) do
    assigns = assign(assigns, :groups, panel_groups(assigns.entries, assigns.hero_gradient))
    assigns = assign(assigns, :size, deck_size(assigns.entries))

    ~H"""
    <div id={"deck-panel-#{@id}-body"} phx-hook="CardLinkPreview" class="flex flex-col gap-4 p-4">
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
        <div class="mt-1 flex items-center gap-2 px-1">
          <span class="font-anton text-[14px] uppercase tracking-[0.05em]">
            <span class={deck_size_class(@size)}>{@size}</span>
            <span class="text-base-content/45">/ 40–50 cards</span>
          </span>
          <.link
            navigate={~p"/decks/#{@deck.id}"}
            class="ml-auto font-barlow-condensed text-[13px] font-bold uppercase tracking-[0.08em] text-base-content/60 hover:text-base-content"
          >
            View deck →
          </.link>
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

      <!-- grouped card list (mirrors the deck page's "In This Deck") -->
      <div :for={g <- @groups}>
        <div class="mb-2 font-anton text-[12px] uppercase tracking-[0.06em] text-primary">
          {g.name} · {g.count}
        </div>

        <div
          :if={@card_view == "images"}
          class="grid grid-cols-[repeat(auto-fill,minmax(96px,1fr))] gap-2"
        >
          <div :for={row <- g.cards} class="relative aspect-[63/88]">
            <.link
              navigate={~p"/cards/#{row.card_id}"}
              class="block h-full border-2 border-neutral shadow-comic-sm"
            >
              <.mc_card
                name={row.name}
                aspect={row.aspect_key}
                image_url={row.image_url}
                gradient_from={row.gradient_from}
                gradient_to={row.gradient_to}
                qty={row.qty}
                size="sm"
                show_cost={false}
              />
            </.link>
            <.qty_stepper
              :if={!row.hero?}
              card_id={row.card_id}
              qty={row.qty}
              max={row.max}
              size="sm"
              class="absolute bottom-1 right-1 z-10"
            />
            <span
              :if={row.hero?}
              class="absolute bottom-1 right-1 z-10 flex size-6 items-center justify-center rounded-[4px] bg-base-100/75"
              title="Locked to the hero set"
            >
              <.icon name="hero-lock-closed" class="size-3 text-white/60" />
            </span>
          </div>
        </div>

        <div :if={@card_view == "list"} class="divide-y divide-neutral/40">
          <div :for={row <- g.cards} class="flex min-h-[40px] items-center gap-2 px-1 py-1">
            <.row_cost cost={row.cost} />
            <.icon
              :if={row.hero?}
              name="hero-user-solid"
              class="size-3 flex-none text-aspect-hero"
            />
            <span :if={!row.hero?} class={["size-2.5 flex-none", row.aspect_bg]}></span>
            <.link
              navigate={~p"/cards/#{row.card_id}"}
              class="min-w-0 truncate font-barlow-condensed text-[14px] font-semibold text-base-content/85 hover:text-base-content"
            >
              {row.name}
            </.link>
            <span class="flex-1"></span>
            <span class="flex-none font-ibm-mono text-[13px] text-base-content/50">
              ×{row.qty}
            </span>
            <!-- pips column: always rendered so every row's icons share one
                 right edge, independent of what the controls column holds -->
            <span class="flex w-8 flex-none items-center justify-end gap-1">
              <span
                :for={{color_class, glyph} <- row.pips}
                class={["font-champions text-[13px] leading-none", color_class]}
              >
                {glyph}
              </span>
            </span>
            <!-- controls column: fixed width whether it holds a lock or steppers -->
            <span class="flex w-[84px] flex-none items-center justify-end gap-0.5 sm:w-[52px]">
              <span :if={row.hero?} title="Locked to the hero set" class="flex justify-end">
                <.icon name="hero-lock-closed" class="size-3 text-base-content/35" />
              </span>
              <button
                :if={!row.hero?}
                type="button"
                data-haptic
                phx-click="dec"
                phx-value-card-id={row.card_id}
                title="Remove a copy"
                class="flex size-10 cursor-pointer items-center justify-center text-base-content/50 transition-colors hover:text-error sm:size-6"
              >
                <.icon name="hero-minus" class="size-4 sm:size-3.5" />
              </button>
              <button
                :if={!row.hero?}
                type="button"
                data-haptic
                phx-click="inc"
                phx-value-card-id={row.card_id}
                disabled={row.qty >= row.max}
                title={(row.qty >= row.max && "At this card's limit") || "Add a copy"}
                class={[
                  "flex size-10 cursor-pointer items-center justify-center transition-colors sm:size-6",
                  (row.qty >= row.max && "cursor-default text-base-content/20") ||
                    "text-base-content/50 hover:text-success"
                ]}
              >
                <.icon name="hero-plus" class="size-4 sm:size-3.5" />
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
    </div>
    """
  end

  # One formatting-toolbar button. The DescriptionEditor hook owns the
  # behavior via data-md-cmd (delegated mousedown, so the textarea keeps
  # focus); no LiveView events are involved.
  attr :cmd, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp md_tool(assigns) do
    ~H"""
    <button
      type="button"
      data-md-cmd={@cmd}
      data-haptic
      title={@title}
      aria-label={@title}
      class="flex h-11 min-w-11 cursor-pointer items-center justify-center px-2 font-barlow-condensed text-[14px] font-bold text-base-content/60 transition-colors hover:text-primary sm:h-7 sm:min-w-7 sm:px-1.5 sm:text-[13px]"
    >
      {render_slot(@inner_block)}
    </button>
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
