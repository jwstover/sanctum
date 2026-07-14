defmodule SanctumWeb.CardLive.Pool do
  @moduledoc """
  Public "Card Pool" — every player card with full text and stats, filterable
  by name, aspect, and type. The comic-dossier counterpart to the admin card
  table.
  """
  use SanctumWeb, :live_view

  require Ash.Query

  import SanctumWeb.Components.HealthBadge
  import SanctumWeb.Components.StatBadge

  alias SanctumWeb.Components.Card, as: CardComponent

  @page_size 24

  @aspects [
    {"all", "All", nil},
    {"hero", "Hero", "bg-aspect-hero"},
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
    {"resource", "Resource"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:cards}>
      <.header>
        Card Pool
        <:subtitle>
          Every player card, with full text and stats. Filter by aspect or type to find what you need.
        </:subtitle>
      </.header>

      <!-- controls -->
      <div class="mb-3.5 flex flex-wrap items-center gap-2.5">
        <form phx-change="search" class="relative min-w-[260px] flex-1">
          <span class="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-[17px] text-base-content/40">
            ⌕
          </span>
          <input
            type="text"
            name="query"
            value={@query}
            phx-debounce="200"
            autocomplete="off"
            placeholder="Search cards by name…"
            class="w-full border-[2.5px] border-line bg-black px-3.5 py-2.5 pl-[38px] font-barlow text-[15px] text-base-content outline-none focus:border-primary"
          />
        </form>
        <div class="whitespace-nowrap font-anton text-[15px] uppercase tracking-[0.05em]">
          {@count} <span class="text-base-content/45">/ {@total} cards</span>
        </div>
      </div>

      <!-- aspect filters -->
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

      <!-- type filters -->
      <div class="mb-6 flex flex-wrap gap-1.5">
        <.filter_pill
          :for={{key, label} <- @type_options}
          active={@type == key}
          phx-click="filter_type"
          phx-value-key={key}
        >
          {label}
        </.filter_pill>
      </div>

      <!-- dossier grid -->
      <div
        id="card-pool"
        phx-update="stream"
        phx-viewport-bottom={!@end_of_timeline? && "next-page"}
        class="grid grid-cols-[repeat(auto-fill,minmax(452px,1fr))] items-start gap-[18px]"
      >
        <div
          :for={{dom_id, card} <- @streams.cards}
          id={dom_id}
          class="mc-tile flex items-start gap-[13px] border-2 border-neutral bg-base-200 p-2 shadow-comic"
        >
          <div class="h-[210px] w-[150px] flex-none border-2 border-neutral shadow-comic-sm">
            <.mc_card
              name={card.name}
              cost={card.cost}
              aspect={card.aspect_key}
              image_url={card.image_url}
              gradient_from={card.gradient_from}
              gradient_to={card.gradient_to}
              size="md"
              show_cost={false}
            />
          </div>

          <div class="flex min-w-0 flex-1 flex-col">
            <div class="flex items-start gap-3">
              <div
                :if={card.show_cost}
                class="flex flex-none items-center justify-center rounded-full font-elektra-med text-4xl/normal"
              >
                {card.cost}
              </div>
              <div class="min-w-0 flex-1">
                <div class={[
                  "font-ibm-mono text-[9px] uppercase tracking-[0.2em]",
                  card.aspect_text_class
                ]}>
                  {card.type_name} · {card.aspect_name}
                </div>
                <div class="mt-[3px] font-anton text-[22px] uppercase leading-[0.94]">
                  {card.name}
                </div>
              </div>
            </div>

            <div :if={card.is_ally} class="flex items-start gap-2 w-full">
              <div class="flex flex-grow items-start justify-start">
                <.stat_badge
                  stat={:thw}
                  value={card.thwart}
                  consequential={card.thwart_consequential}
                  size={64}
                />
                <.stat_badge
                  stat={:atk}
                  value={card.attack}
                  consequential={card.attack_consequential}
                  size={64}
                />
              </div>
              <div class="flex items-start justify-end">
                <.health_badge value={card.health} size={52} />
              </div>
            </div>

            <div class="my-2 h-px bg-neutral"></div>

            <div
              :if={card.traits != ""}
              class="flex justify-center mb-1 font-komika text-xs font-semibold uppercase tracking-[0.02em] text-base-content/75"
            >
              {card.traits}
            </div>

            <div class="text-center font-barlow text-[13.5px] leading-[1.5] text-base-content/85">
              {Sanctum.CardText.to_html(card.text)}
            </div>

            <div
              :if={card.flavor}
              class="text-center font-barlow italic text-xs text-base-content/65 my-2"
            >
              {Sanctum.CardText.to_html(card.flavor)}
            </div>

            <div :if={card.pips != []} class="mt-2.5 flex items-center gap-1">
              <span
                :for={{color_class, glyph} <- card.pips}
                class={["font-champions text-2xl leading-none", color_class]}
              >
                {glyph}
              </span>
            </div>
          </div>
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
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    total = count_cards(socket, %{})

    {:ok,
     socket
     |> assign(:page_title, "Card Pool")
     |> assign(:query, "")
     |> assign(:aspect, "all")
     |> assign(:type, "all")
     |> assign(:total, total)
     |> assign(:count, total)
     |> assign(:aspect_options, @aspects)
     |> assign(:type_options, @types)
     |> assign(:offset, 0)
     |> assign(:end_of_timeline?, false)
     |> assign(:hero_colors, load_hero_colors())
     |> stream(:cards, [])
     |> load_page(0, reset: true)}
  end

  # set -> {primary_color, secondary_color} for heroes with a stored palette.
  defp load_hero_colors do
    Sanctum.Heroes.Hero
    |> Ash.read!()
    |> Map.new(fn h -> {h.set, {h.primary_color, h.secondary_color}} end)
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, socket |> assign(:query, query) |> reset_and_load()}
  end

  def handle_event("filter_aspect", %{"key" => key}, socket) do
    {:noreply, socket |> assign(:aspect, key) |> reset_and_load()}
  end

  def handle_event("filter_type", %{"key" => key}, socket) do
    {:noreply, socket |> assign(:type, key) |> reset_and_load()}
  end

  def handle_event("clear", _params, socket) do
    {:noreply,
     socket
     |> assign(query: "", aspect: "all", type: "all")
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
      Sanctum.Games.Card
      |> Ash.Query.for_read(:browse, filters(socket.assigns),
        actor: socket.assigns[:current_user]
      )
      |> Ash.read!(page: [limit: @page_size, offset: offset, count: reset?])

    socket
    |> assign(:offset, offset)
    |> assign(:end_of_timeline?, !page.more?)
    |> then(fn s -> if reset?, do: assign(s, :count, page.count), else: s end)
    |> stream(:cards, Enum.map(page.results, &card_view(&1, socket.assigns.hero_colors)),
      reset: reset?
    )
  end

  defp count_cards(socket, extra_filters) do
    Sanctum.Games.Card
    |> Ash.Query.for_read(:browse, Map.merge(%{aspect: "all", type: "all"}, extra_filters),
      actor: socket.assigns[:current_user]
    )
    |> Ash.read!(page: [limit: 1, offset: 0, count: true])
    |> Map.get(:count)
  end

  defp filters(assigns) do
    %{query: assigns.query, aspect: assigns.aspect, type: assigns.type}
  end

  # Builds the display map the tile renders from, derived from the primary side.
  defp card_view(%{primary_side: side} = card, hero_colors) do
    aspect_key = display_aspect(side)
    {gradient_from, gradient_to} = hero_gradient(card.set, hero_colors)

    resources =
      [
        energy: side.resource_energy_count,
        mental: side.resource_mental_count,
        physical: side.resource_physical_count,
        wild: side.resource_wild_count
      ]
      |> Enum.flat_map(fn {res, n} -> List.duplicate(res, n || 0) end)

    %{
      id: card.id,
      name: side.name,
      type: side.type,
      cost: side.cost,
      show_cost: side.type != :resource and not is_nil(side.cost),
      aspect_key: aspect_key,
      aspect_name: aspect_name(aspect_key, card.set),
      gradient_from: gradient_from,
      gradient_to: gradient_to,
      type_name: type_name(side.type),
      aspect_text_class: CardComponent.aspect_classes(aspect_key).text,
      resources: resources,
      pips: CardComponent.resource_pips(resources),
      traits: format_traits(side.traits),
      text: side.text || "",
      flavor: Map.get(side, :flavor, ""),
      is_ally: side.type == :ally,
      attack: stat_value(side.attack),
      attack_consequential: stat_consequential(side.attack),
      thwart: stat_value(side.thwart),
      thwart_consequential: stat_consequential(side.thwart),
      health: stat_value(side.health),
      image_url: side.image_url
    }
  end

  # Resolve a hero's gradient from stored MarvelCDB colors, falling back to a
  # stable slug-derived gradient for sets with no stored palette.
  defp hero_gradient(set, hero_colors) do
    case Map.get(hero_colors, set) do
      {from, to} when is_binary(from) and is_binary(to) -> {from, to}
      _ -> CardComponent.fallback_gradient(set)
    end
  end

  defp stat_value(nil), do: nil
  defp stat_value(%{value: value}), do: value

  defp stat_consequential(%{consequential: n}) when is_integer(n), do: n
  defp stat_consequential(_), do: 0

  defp format_traits(traits) when is_list(traits), do: Enum.join(traits, " · ")
  defp format_traits(_), do: ""

  # The display key drives tile color/label: aspect cards (including pool) use
  # their aspect; every other pool (hero signature, basic) uses its ownership.
  defp display_aspect(%{ownership: :player, aspect: aspect}) when not is_nil(aspect), do: aspect
  defp display_aspect(%{ownership: :hero}), do: :hero
  defp display_aspect(%{ownership: :basic}), do: :basic
  defp display_aspect(%{aspect: aspect}) when not is_nil(aspect), do: aspect
  defp display_aspect(_), do: :basic

  # Hero signature cards have no aspect; name them after their hero set instead.
  defp aspect_name(:hero, set), do: hero_name(set)
  defp aspect_name(aspect, _set), do: aspect |> to_string() |> String.capitalize()

  defp hero_name(set) when is_binary(set) and set != "",
    do: set |> String.split("_") |> Enum.map_join(" ", &String.capitalize/1)

  defp hero_name(_), do: "Hero"

  defp type_name(nil), do: "Card"
  defp type_name(type), do: type |> to_string() |> String.replace("_", " ") |> String.capitalize()
end
