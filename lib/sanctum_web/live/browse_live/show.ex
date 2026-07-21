defmodule SanctumWeb.BrowseLive.Show do
  @moduledoc """
  A single product's contents, grouped by card-set role: villains, main scheme,
  modular sets, encounter sets, heroes (each paired with its nemesis set), and a
  Player Cards bucket for the aspect/basic cards that ship in the product but
  belong to no card set.
  """
  use SanctumWeb, :live_view

  require Ash.Query

  alias Sanctum.Catalog
  alias SanctumWeb.Components.Card, as: CardComponent

  @aspect_order %{
    hero: 0,
    aggression: 1,
    justice: 2,
    leadership: 3,
    protection: 4,
    pool: 5,
    basic: 6,
    encounter: 7
  }

  @impl true
  def mount(%{"pack" => code}, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Browse")
      # nil until the async load lands — drives the loading/skeleton UI.
      |> assign(:pack, nil)
      |> assign(:villain_groups, [])
      |> assign(:encounter_groups, [])
      |> assign(:sections, [])
      |> assign(:modular_groups, [])
      |> assign(:player_groups, [])
      |> assign(:scroll_restore_pending?, false)
      # nil owned_ids = anonymous; no collection UI renders at all.
      |> assign(:owned_ids, nil)
      |> assign(:total_cards, 0)
      |> assign(:pack_owned, false)

    actor = socket.assigns[:current_user]

    # Skip the (heavy) product load on the static render; it runs asynchronously
    # once the socket connects so the shell paints immediately.
    socket =
      if connected?(socket),
        do: start_async(socket, :load_pack, fn -> load_pack(code, actor) end),
        else: socket

    {:ok, socket}
  end

  # Pushed by the ScrollRestore hook when the user arrives with a saved scroll
  # position. The page renders asynchronously, so hold the confirmation until
  # the pack load lands and the content exists at its full height.
  @impl true
  def handle_event("restore-scroll", _params, socket) do
    if socket.assigns.pack do
      {:noreply, push_event(socket, "sanctum:scroll-restore", %{})}
    else
      {:noreply, assign(socket, :scroll_restore_pending?, true)}
    end
  end

  def handle_event("toggle_pack_owned", _params, %{assigns: %{current_user: user}} = socket)
      when not is_nil(user) do
    pack = socket.assigns.pack

    if socket.assigns.pack_owned,
      do: Sanctum.Collections.remove_pack(pack.id, user),
      else: Sanctum.Collections.add_pack!(pack.id, actor: user)

    # Pack membership changes every card's derived state; re-derive the page.
    {owned_ids, total_cards, pack_owned} = collection_state(pack, user)

    {:noreply,
     socket
     |> assign(:owned_ids, owned_ids)
     |> assign(:total_cards, total_cards)
     |> assign(:pack_owned, pack_owned)}
  end

  def handle_event(
        "toggle_card_owned",
        %{"id" => card_id},
        %{assigns: %{current_user: user}} = socket
      )
      when not is_nil(user) do
    owned_ids =
      if Sanctum.Collections.toggle_card(card_id, user),
        do: MapSet.put(socket.assigns.owned_ids, card_id),
        else: MapSet.delete(socket.assigns.owned_ids, card_id)

    {:noreply, assign(socket, :owned_ids, owned_ids)}
  end

  def handle_event("toggle_" <> _, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:load_pack, {:ok, {:ok, data}}, socket) do
    socket =
      socket
      |> assign(:page_title, data.page_title)
      |> assign(:pack, data.pack)
      |> assign(:villain_groups, data.villain_groups)
      |> assign(:encounter_groups, data.encounter_groups)
      |> assign(:sections, data.sections)
      |> assign(:modular_groups, data.modular_groups)
      |> assign(:player_groups, data.player_groups)
      |> assign(:owned_ids, data.owned_ids)
      |> assign(:total_cards, data.total_cards)
      |> assign(:pack_owned, data.pack_owned)

    socket =
      if socket.assigns.scroll_restore_pending? do
        socket
        |> assign(:scroll_restore_pending?, false)
        |> push_event("sanctum:scroll-restore", %{})
      else
        socket
      end

    # Sections carry their card-set code as a DOM id (/browse/cw#spider_man),
    # but the fragment never reaches the server and the anchor target only
    # exists now that the async load has rendered — nudge the client to honor
    # it (a no-op without a fragment; ScrollRestore skips saved positions when
    # one is present).
    {:noreply, push_event(socket, "sanctum:scroll-to-hash", %{})}
  end

  def handle_async(:load_pack, {:ok, {:error, code}}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Unknown product “#{code}”.")
     |> push_navigate(to: ~p"/browse")}
  end

  def handle_async(:load_pack, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Couldn’t load product: #{inspect(reason)}")
     |> push_navigate(to: ~p"/browse")}
  end

  # The whole product view: the pack with its nested card sets/sides, plus every
  # derived section grouping. Returns `{:error, code}` for an unknown code so
  # handle_async can redirect.
  defp load_pack(code, actor) do
    case Catalog.get_pack_by_code(code,
           load: [:wave, :card_total, card_sets: [cards: [:primary_side, :card_sides]]]
         ) do
      {:ok, %Catalog.Pack{} = pack} ->
        hero_colors = Sanctum.Heroes.hero_color_map()
        {owned_ids, total_cards, pack_owned} = collection_state(pack, actor)

        {:ok,
         %{
           page_title: pack.name || pack.code,
           pack: pack,
           villain_groups: villain_groups(pack, hero_colors),
           encounter_groups: encounter_groups(pack, hero_colors),
           sections: build_sections(pack, hero_colors),
           modular_groups: modular_groups(pack, hero_colors),
           player_groups: player_card_groups(pack, hero_colors),
           owned_ids: owned_ids,
           total_cards: total_cards,
           pack_owned: pack_owned
         }}

      _ ->
        {:error, code}
    end
  end

  # One query for the whole page: which of this pack's cards the user owns
  # (per-card overrides and reprints included via the :owned calc), plus the
  # distinct card count for the "X / Y owned" progress line.
  defp collection_state(_pack, nil), do: {nil, 0, false}

  defp collection_state(pack, actor) do
    cards =
      Sanctum.Games.Card
      |> Ash.Query.filter(pack_id == ^pack.id)
      |> Ash.Query.load(:owned)
      |> Ash.read!(actor: actor)

    owned_ids = cards |> Enum.filter(& &1.owned) |> MapSet.new(& &1.id)

    {owned_ids, length(cards), Sanctum.Collections.pack_owned?(pack.id, actor)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:browse}>
      <div id="scroll-restore" phx-hook="ScrollRestore"></div>
      <!-- first-load skeleton -->
      <div :if={@pack == nil} class="flex flex-col gap-6">
        <div class="h-9 w-1/2 max-w-md animate-pulse bg-base-300"></div>
        <div class="h-4 w-1/3 max-w-xs animate-pulse bg-base-300"></div>
        <.art_grid_skeleton count={8} />
      </div>

      <div :if={@pack != nil}>
        <.header>
          <.link navigate={~p"/browse"} class="text-base-content/45 hover:text-primary">
            Browse
          </.link>
          <span class="text-base-content/30">/</span>
          {@pack.name || @pack.code}

          <:actions :if={@current_user}>
            <.collection_toggle owned={@pack_owned} event="toggle_pack_owned" id={@pack.id} />
          </:actions>
        </.header>

        <div class="flex flex-col gap-9">
          <.grouped_section
            title="Villains"
            description="Scenario villain sets included in this product."
            groups={@villain_groups}
            owned_ids={@owned_ids}
          />

          <.grouped_section
            title="Encounter Sets"
            description="Standard, expert, and leader encounter sets included in this product."
            groups={@encounter_groups}
            owned_ids={@owned_ids}
          />

          <.card_section
            :for={section <- @sections}
            title={section.title}
            subtitle={section.subtitle}
            cards={section.cards}
            anchor={section.code}
            owned_ids={@owned_ids}
          />

          <.grouped_section
            title="Player Cards"
            description="Aspect and basic cards included in this product."
            groups={@player_groups}
            owned_ids={@owned_ids}
          />

          <.grouped_section
            title="Modular Sets"
            description="Encounter modules included in this product."
            groups={@modular_groups}
            owned_ids={@owned_ids}
          />
        </div>

        <.panel
          :if={
            @sections == [] and @villain_groups == [] and @encounter_groups == [] and
              @player_groups == [] and @modular_groups == []
          }
          class="mt-2 p-6 text-center"
        >
          <p class="font-barlow-condensed text-lg text-base-content/60">
            No cards have been synced for this product yet.
          </p>
        </.panel>
      </div>
    </Layouts.app>
    """
  end

  # A yellow top-level category heading over one :sub card_section per group —
  # the shared shape for Villains, Player Cards, and Modular Sets.
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :groups, :list, required: true
  attr :owned_ids, :any, default: nil

  defp grouped_section(assigns) do
    ~H"""
    <section :if={@groups != []}>
      <h2 class={[
        "font-anton text-[22px] uppercase tracking-[0.03em] text-primary",
        (@description && "mb-1") || "mb-4"
      ]}>
        {@title}
      </h2>
      <p :if={@description} class="mb-4 font-barlow-condensed text-base-content/50">
        {@description}
      </p>
      <div class="flex flex-col gap-6">
        <.card_section
          :for={group <- @groups}
          title={group.title}
          cards={group.cards}
          level={:sub}
          anchor={group[:code]}
          owned_ids={@owned_ids}
        />
      </div>
    </section>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :cards, :list, required: true
  attr :level, :atom, default: :top
  attr :owned_ids, :any, default: nil, doc: "MapSet of owned card ids; nil hides collection UI"

  attr :anchor, :string,
    default: nil,
    doc: "card-set code used as the section's DOM id, so /browse/:pack#<code> can land here"

  defp card_section(assigns) do
    ~H"""
    <section id={@anchor} class="scroll-mt-24 lg:scroll-mt-6">
      <div class="mb-3.5 flex flex-wrap items-baseline gap-x-3 border-b-2 border-neutral pb-2">
        <h2 class={[
          "font-anton uppercase leading-none tracking-[0.03em]",
          @level == :top && "text-[22px] text-primary",
          @level == :sub && "text-[17px] text-base-content/85"
        ]}>
          {@title}
        </h2>
        <span :if={@subtitle} class="font-barlow-condensed text-base uppercase text-base-content/45">
          {@subtitle}
        </span>
        <span class="ml-auto font-ibm-mono text-[11px] text-base-content/40">
          {Enum.sum_by(@cards, & &1.quantity)} cards
        </span>
      </div>

      <div class="flex flex-wrap gap-2.5">
        <div
          :for={card <- @cards}
          class={
            [
              "relative h-[210px] flex-none",
              # Fixed height keeps every card's baseline aligned; the width follows
              # the card's real aspect (7/5 landscape vs 5/7 portrait) so mc_card's
              # object-cover image shows the full scan without cropping.
              (card.is_landscape && "w-[294px]") || "w-[150px]"
            ]
          }
        >
          <.link
            navigate={~p"/cards/#{card.card_id}"}
            class="block h-full w-full border-2 border-neutral shadow-comic-sm"
          >
            <.mc_card
              name={card.name}
              type={card.type}
              aspect={card.aspect_key}
              resources={card.resources}
              qty={card.quantity}
              image_url={card.image_url}
              gradient_from={card.gradient_from}
              gradient_to={card.gradient_to}
              size="md"
              show_cost={false}
            />
          </.link>
          <.collection_toggle
            :if={@owned_ids && card.quantity > 0}
            compact
            owned={MapSet.member?(@owned_ids, card.card_id)}
            event="toggle_card_owned"
            id={card.card_id}
            class="absolute bottom-1.5 right-1.5 z-10"
          />
        </div>
      </div>
    </section>
    """
  end

  # The flat middle sections: Main Scheme, then each hero followed by its
  # nemesis. Villains, encounter sets, and modular sets render as their own
  # grouped blocks (see *_groups/2). Nemesis sets whose hero is in this product
  # render right after that hero; orphaned nemesis sets render standalone.
  defp build_sections(pack, hero_colors) do
    sets = pack.card_sets
    hero_sets = Enum.filter(sets, &(&1.set_type == :hero))
    paired_nemesis_ids = nemesis_ids_for(sets, hero_sets)

    main_scheme_sets = Enum.filter(sets, &(&1.set_type == :main_scheme))

    main_scheme_sections =
      case cards_from_sets(main_scheme_sets, hero_colors) do
        [] ->
          []

        cards ->
          code = main_scheme_sets |> List.first() |> then(&(&1 && &1.code))
          [%{title: "Main Scheme", subtitle: nil, cards: cards, code: code}]
      end

    hero_sections = Enum.flat_map(hero_sets, &hero_and_nemesis_sections(&1, sets, hero_colors))

    standalone_nemesis =
      sets
      |> Enum.filter(&(&1.set_type == :nemesis and &1.id not in paired_nemesis_ids))
      |> Enum.map(
        &%{
          title: &1.name || "Nemesis",
          subtitle: "Nemesis",
          cards: view_cards(&1.cards, hero_colors),
          code: &1.code
        }
      )

    main_scheme_sections ++ hero_sections ++ standalone_nemesis
  end

  # A hero and its nemesis render as adjacent-but-separate sections: the hero's
  # signature set, then its nemesis set right after.
  defp hero_and_nemesis_sections(hero_set, sets, hero_colors) do
    nemesis = Enum.find(sets, &(&1.set_type == :nemesis and &1.hero_set_id == hero_set.id))

    hero_section = %{
      title: hero_set.name || "Hero",
      subtitle: "Hero",
      cards: view_cards(hero_set.cards, hero_colors),
      code: hero_set.code
    }

    nemesis_section =
      if nemesis do
        [
          %{
            title: nemesis.name || "Nemesis",
            subtitle: "Nemesis",
            cards: view_cards(nemesis.cards, hero_colors),
            code: nemesis.code
          }
        ]
      else
        []
      end

    [hero_section | nemesis_section]
  end

  defp nemesis_ids_for(sets, hero_sets) do
    hero_ids = MapSet.new(hero_sets, & &1.id)

    for s <- sets, s.set_type == :nemesis, s.hero_set_id in hero_ids, into: MapSet.new(), do: s.id
  end

  defp cards_from_sets(sets, hero_colors) do
    sets |> Enum.flat_map(& &1.cards) |> view_cards(hero_colors)
  end

  # Encounter set types that make up the "Encounter Sets" block (standard/expert
  # difficulty sets, PvP "leader" sets, evidence sets).
  @encounter_set_types [:standard, :expert, :leader, :evidence]

  # One group per villain (scenario) set.
  defp villain_groups(pack, hero_colors), do: set_groups(pack, [:villain], hero_colors)

  # One group per encounter set (standard/expert/leader/evidence).
  defp encounter_groups(pack, hero_colors),
    do: set_groups(pack, @encounter_set_types, hero_colors)

  # One group per modular set (kept separate rather than merged).
  defp modular_groups(pack, hero_colors), do: set_groups(pack, [:modular], hero_colors)

  defp set_groups(pack, set_types, hero_colors) do
    pack.card_sets
    |> Enum.filter(&(&1.set_type in set_types))
    # Order by each set's lowest card code — roughly the pack's printed order, so
    # the headline set leads rather than whatever sorts alphabetically.
    |> Enum.sort_by(&min_card_code/1)
    |> Enum.map(
      &%{title: &1.name || &1.code, cards: view_cards(&1.cards, hero_colors), code: &1.code}
    )
    |> Enum.reject(&(&1.cards == []))
  end

  defp min_card_code(%{cards: []}), do: ""
  defp min_card_code(%{cards: cards}), do: cards |> Enum.map(& &1.code) |> Enum.min()

  # Player/basic cards belong to no card set; bucket them by aspect.
  defp player_card_groups(pack, hero_colors) do
    cards =
      Sanctum.Games.Card
      |> Ash.Query.filter(pack_id == ^pack.id and is_nil(card_set_id))
      |> Ash.Query.load([:primary_side, :card_sides])
      |> Ash.read!()

    cards
    |> Enum.group_by(&display_aspect(&1.primary_side))
    |> Enum.sort_by(fn {aspect, _} -> Map.get(@aspect_order, aspect, 99) end)
    |> Enum.map(fn {aspect, cards} ->
      %{title: aspect_label(aspect), cards: view_cards(cards, hero_colors)}
    end)
  end

  defp view_cards(cards, hero_colors) do
    cards
    |> Enum.flat_map(&card_views(&1, hero_colors))
    |> Enum.sort_by(& &1.sort_key)
  end

  # Display maps for every side of a card. Single-sided cards yield one view;
  # multi-sided cards (identities, main schemes) yield one per face, primary
  # side first, so the pack page shows front and back.
  defp card_views(%{card_sides: sides} = card, hero_colors)
       when is_list(sides) and sides != [] do
    {gradient_from, gradient_to} = hero_gradient(card.set, hero_colors)

    sides
    |> Enum.sort_by(&{!&1.is_primary_side, &1.side_identifier || ""})
    |> Enum.map(fn side ->
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
        code: side.code,
        # Keep a card's faces adjacent and primary-first, then order cards among
        # themselves by the canonical code.
        sort_key: {card.code, (side.is_primary_side && 0) || 1, side.side_identifier || ""},
        name: side.name,
        type: side.type,
        aspect_key: display_aspect(side),
        is_landscape: CardComponent.landscape_type?(side.type),
        resources: resources,
        # MarvelCDB's per-card `quantity` (copies in the product) is stored on
        # Card.deck_limit; show the ×N badge only on the primary face so a
        # double-sided card isn't counted twice in the section total.
        quantity: (side.is_primary_side && (card.deck_limit || 1)) || 0,
        gradient_from: gradient_from,
        gradient_to: gradient_to,
        image_url: side.image_url
      }
    end)
  end

  defp card_views(_card, _hero_colors), do: []

  defp hero_gradient(set, hero_colors) do
    case Map.get(hero_colors, set) do
      {from, to} when is_binary(from) and is_binary(to) -> {from, to}
      _ -> CardComponent.fallback_gradient(set)
    end
  end

  # Mirrors CardLive.Pool: aspect cards use their aspect; other pools use
  # ownership; encounter/campaign share the encounter accent.
  defp display_aspect(nil), do: :basic
  defp display_aspect(%{ownership: :player, aspect: aspect}) when not is_nil(aspect), do: aspect
  defp display_aspect(%{ownership: :hero}), do: :hero
  defp display_aspect(%{ownership: :basic}), do: :basic
  defp display_aspect(%{ownership: :encounter}), do: :encounter
  defp display_aspect(%{ownership: :campaign}), do: :encounter
  defp display_aspect(%{aspect: aspect}) when not is_nil(aspect), do: aspect
  defp display_aspect(_), do: :basic

  defp aspect_label(:hero), do: "Hero"
  defp aspect_label(:encounter), do: "Encounter"
  defp aspect_label(aspect), do: aspect |> to_string() |> String.capitalize()
end
