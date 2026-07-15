defmodule SanctumWeb.CardLive.Pool do
  @moduledoc """
  Public "Card Pool" — every card side in the game (player *and* encounter) with
  full text and stats, filterable by name, aspect, and type. The comic-dossier
  counterpart to the admin card table.
  """
  use SanctumWeb, :live_view

  require Ash.Query

  import SanctumWeb.Components.HandSizeBadge
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
    {"resource", "Resource"},
    {"player_side_scheme", "Side Scheme"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:cards}>
      <.header>
        Card Pool
        <:subtitle>
          Every card in the game — player and encounter — with full text and stats. Filter by aspect or type to find what you need.
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
            class="w-full border-[2.5px] border-line bg-black px-3.5 py-2.5 pl-[38px] font-barlow text-base text-base-content outline-none focus:border-primary sm:text-[15px]"
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
        class="grid grid-cols-1 items-start gap-[18px] sm:grid-cols-[repeat(auto-fill,minmax(452px,1fr))]"
      >
        <div
          :for={{dom_id, side} <- @streams.cards}
          id={dom_id}
          class="mc-tile flex flex-col items-start gap-[13px] border-2 border-neutral bg-base-200 p-2 shadow-comic sm:flex-row"
        >
          <div class={[
            "flex-none self-center border-2 border-neutral shadow-comic-sm sm:self-start",
            (side.is_landscape && "h-[150px] w-[210px]") || "h-[210px] w-[150px]"
          ]}>
            <.mc_card
              name={side.name}
              type={side.type}
              cost={side.cost}
              aspect={side.aspect_key}
              image_url={side.image_url}
              gradient_from={side.gradient_from}
              gradient_to={side.gradient_to}
              size="md"
              show_cost={false}
            />
          </div>

          <div class="flex min-w-0 flex-1 flex-col">
            <div class="h-12 flex items-start gap-3">
              <div
                :if={side.show_cost}
                class="flex flex-none items-center justify-center rounded-full font-elektra-med text-4xl/normal"
              >
                {side.cost}
              </div>
              <div class="min-w-0 flex-1">
                <div class={[
                  "font-ibm-mono text-[9px] uppercase tracking-[0.2em]",
                  side.aspect_text_class
                ]}>
                  {side.type_name} · {side.aspect_name}
                </div>
                <div class="mt-[3px] flex items-baseline gap-2">
                  <div class="min-w-0 flex-1 font-anton text-[22px] uppercase leading-[0.94]">
                    {side.name}
                  </div>
                  <div
                    :if={side.stage_label}
                    class="flex-none font-elektra-med text-[18px] leading-none text-white"
                  >
                    {side.stage_label}
                  </div>
                </div>
              </div>
            </div>

            <div :if={side.is_ally} class="flex items-start gap-2 w-full">
              <div class="flex flex-grow items-start justify-start">
                <.stat_badge
                  stat={:thw}
                  value={side.thwart}
                  consequential={side.thwart_consequential}
                  size={64}
                />
                <.stat_badge
                  stat={:atk}
                  value={side.attack}
                  consequential={side.attack_consequential}
                  size={64}
                />
              </div>
              <div class="flex items-start justify-end">
                <.health_badge value={side.health} size={52} />
              </div>
            </div>

            <div :if={side.is_hero} class="flex items-start gap-2 w-full">
              <div class="flex flex-grow items-start justify-start">
                <.stat_badge stat={:thw} value={side.thwart} size={64} hero={true} />
                <.stat_badge stat={:atk} value={side.attack} size={64} hero={true} />
                <.stat_badge stat={:def} value={side.defense} size={64} hero={true} />
              </div>
              <div class="flex items-start justify-end">
                <.health_badge value={side.health} size={52} />
              </div>
            </div>

            <div :if={side.is_villain or side.is_minion} class="flex items-start gap-2 w-full">
              <div class="flex flex-grow items-start justify-start">
                <.stat_badge stat={:thw} value={side.scheme} label="SCH" size={64} />
                <.stat_badge stat={:atk} value={side.attack} star={side.attack_star} size={64} />
              </div>
              <div :if={side.health} class="flex items-start justify-end">
                <.health_badge value={side.health} player={side.health_per_player} size={52} />
              </div>
            </div>

            <div
              :if={side.is_scheme and (side.start_threat || side.escalation_threat)}
              class="mb-1 w-full"
            >
              <div class="inline-flex -skew-x-[9deg] border-2 border-white bg-base-100 shadow-comic-sm">
                <.scheme_cell value={side.start_threat} per_player={side.start_threat_pp} />
                <div :if={side.is_main_scheme} class="w-px self-stretch bg-white"></div>
                <.scheme_cell
                  :if={side.is_main_scheme}
                  value={side.escalation_threat}
                  per_player={side.escalation_threat_pp}
                  sign
                />
                <div :if={side.is_main_scheme} class="w-px self-stretch bg-white"></div>
                <.scheme_cell
                  :if={side.is_main_scheme}
                  value={side.threat_target}
                  per_player={side.threat_per_player}
                />
              </div>
            </div>

            <div class="my-2 h-px bg-neutral"></div>

            <div
              :if={side.traits != ""}
              class="flex justify-center mb-1 font-komika text-xs font-semibold uppercase tracking-[0.02em] text-base-content/75"
            >
              {side.traits}
            </div>

            <div class="font-barlow text-[13.5px] leading-[1.5] text-base-content/85">
              {Sanctum.CardText.to_html(side.text)}
            </div>

            <div
              :if={side.flavor}
              class="text-center font-barlow italic text-xs text-base-content/65 my-2"
            >
              {Sanctum.CardText.to_html(side.flavor)}
            </div>

            <div
              :if={side.pips != [] or (side.is_hero and side.hand_size)}
              class="mt-2.5 flex items-center gap-1"
            >
              <span
                :for={{color_class, glyph} <- side.pips}
                class={["font-champions text-2xl leading-none", color_class]}
              >
                {glyph}
              </span>
              <.hand_size_badge
                :if={side.is_hero and side.hand_size}
                value={side.hand_size}
                class="ml-auto text-base-content/75"
              />
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

  # One segment of the main-scheme threat plate: starting threat, escalation,
  # then threshold. The ChampionsIcons per-player icon is appended when the value
  # scales per hero. Counter-skewed so the text stays upright in the comic plate.
  attr :value, :any, default: nil
  attr :per_player, :boolean, default: false
  attr :sign, :boolean, default: false, doc: "prefix positive values with + (escalation threat)"

  defp scheme_cell(assigns) do
    ~H"""
    <div class="flex skew-x-[9deg] items-baseline gap-0.5 px-2 font-elektra-med text-2xl/snug">
      {scheme_value(@value, @sign)}
      <span :if={@per_player} class="font-champions text-xs leading-none text-white">
        v
      </span>
    </div>
    """
  end

  defp scheme_value(nil, _sign), do: "—"
  defp scheme_value(v, true) when is_integer(v) and v > 0, do: "+#{v}"
  defp scheme_value(v, _sign), do: v

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
      Sanctum.Games.CardSide
      |> Ash.Query.for_read(:browse, filters(socket.assigns),
        actor: socket.assigns[:current_user]
      )
      |> Ash.read!(page: [limit: @page_size, offset: offset, count: reset?])

    socket
    |> assign(:offset, offset)
    |> assign(:end_of_timeline?, !page.more?)
    |> then(fn s -> if reset?, do: assign(s, :count, page.count), else: s end)
    |> stream(
      :cards,
      Enum.map(page.results, &side_view(&1, socket.assigns.hero_colors)),
      reset: reset?
    )
  end

  defp count_cards(socket, extra_filters) do
    Sanctum.Games.CardSide
    |> Ash.Query.for_read(:browse, Map.merge(%{aspect: "all", type: "all"}, extra_filters),
      actor: socket.assigns[:current_user]
    )
    |> Ash.read!(page: [limit: 1, offset: 0, count: true])
    |> Map.get(:count)
  end

  defp filters(assigns) do
    %{query: assigns.query, aspect: assigns.aspect, type: assigns.type}
  end

  # Builds the display map for a single card face. Each side is streamed as its
  # own tile, so multi-sided cards appear as separate cards.
  defp side_view(side, hero_colors) do
    card = side.card
    {gradient_from, gradient_to} = hero_gradient(card.set, hero_colors)
    aspect_key = display_aspect(side)

    resources =
      [
        energy: side.resource_energy_count,
        mental: side.resource_mental_count,
        physical: side.resource_physical_count,
        wild: side.resource_wild_count
      ]
      |> Enum.flat_map(fn {res, n} -> List.duplicate(res, n || 0) end)

    %{
      id: side.id,
      name: side.name,
      type: side.type,
      is_landscape: CardComponent.landscape_type?(side.type),
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
      is_hero: side.type == :hero,
      is_villain: side.type == :villain,
      is_minion: side.type == :minion,
      is_scheme: side.type in [:main_scheme, :side_scheme, :player_side_scheme],
      hand_size: side.hand_size,
      attack: stat_value(side.attack),
      attack_star: stat_star(side.attack),
      attack_consequential: stat_consequential(side.attack),
      thwart: stat_value(side.thwart),
      thwart_consequential: stat_consequential(side.thwart),
      defense: stat_value(side.defense),
      health: stat_value(side.health),
      health_per_player: stat_per_player(side.health),
      scheme: side.scheme,
      is_main_scheme: side.type == :main_scheme,
      threat_target: threat_target(side),
      threat_per_player: threat_target_per_player?(side),
      start_threat: stat_value(side.base_threat),
      start_threat_pp: stat_per_player(side.base_threat),
      escalation_threat: stat_value(side.escalation_threat),
      escalation_threat_pp: stat_per_player(side.escalation_threat),
      stage_label: stage_label(side),
      image_url: side.image_url
    }
  end

  # Main-scheme stage + side, e.g. "1A"/"2B", from the printed stage number and
  # side identifier.
  defp stage_label(%{type: :main_scheme, stage: stage, side_identifier: side})
       when is_integer(stage) and is_binary(side),
       do: "#{stage}#{String.upcase(side)}"

  defp stage_label(_), do: nil

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

  defp stat_star(%{star: true}), do: true
  defp stat_star(_), do: false

  # A per-player-scaling stat (X per hero) is marked with the champions star.
  defp stat_per_player(%{scaling: scaling}) when scaling in [:per_player, "per_player"], do: true
  defp stat_per_player(_), do: false

  # A scheme's threat target: main schemes carry it in `max_threat`; side schemes
  # (and player side schemes) carry it in `base_threat`.
  defp threat_target(%{max_threat: %{value: v}}), do: v
  defp threat_target(%{base_threat: %{value: v}}), do: v
  defp threat_target(_), do: nil

  defp threat_target_per_player?(%{max_threat: stat}) when not is_nil(stat),
    do: stat_per_player(stat)

  defp threat_target_per_player?(%{base_threat: stat}) when not is_nil(stat),
    do: stat_per_player(stat)

  defp threat_target_per_player?(_), do: false

  defp format_traits(traits) when is_list(traits), do: Enum.join(traits, " · ")
  defp format_traits(_), do: ""

  # The display key drives tile color/label: aspect cards (including pool) use
  # their aspect; every other pool uses its ownership. Encounter and campaign
  # cards share the encounter accent.
  defp display_aspect(%{ownership: :player, aspect: aspect}) when not is_nil(aspect), do: aspect
  defp display_aspect(%{ownership: :hero}), do: :hero
  defp display_aspect(%{ownership: :basic}), do: :basic
  defp display_aspect(%{ownership: :encounter}), do: :encounter
  defp display_aspect(%{ownership: :campaign}), do: :encounter
  defp display_aspect(%{aspect: aspect}) when not is_nil(aspect), do: aspect
  defp display_aspect(_), do: :basic

  # Hero signature cards have no aspect; name them after their hero set instead.
  defp aspect_name(:hero, set), do: hero_name(set)
  defp aspect_name(:encounter, _set), do: "Encounter"
  defp aspect_name(aspect, _set), do: aspect |> to_string() |> String.capitalize()

  defp hero_name(set) when is_binary(set) and set != "",
    do: set |> String.split("_") |> Enum.map_join(" ", &String.capitalize/1)

  defp hero_name(_), do: "Hero"

  defp type_name(nil), do: "Card"
  defp type_name(type), do: type |> to_string() |> String.replace("_", " ") |> String.capitalize()
end
