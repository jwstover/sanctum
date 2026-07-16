defmodule SanctumWeb.Components.CardSideTile do
  @moduledoc """
  The dossier tile for a single card face — the `mc_card` art beside the
  printed name, comic stat badges, threat plate, traits, text, and flavor.
  Shared by the public Card Pool grid and the public card detail page.

  Consumers build the tile's display map with `side_view/2` from a `CardSide`
  (with its `card` loaded) and the hero-color palette map
  (`Sanctum.Heroes.hero_color_map/0`).
  """
  use Phoenix.Component

  import SanctumWeb.Components.Card
  import SanctumWeb.Components.HandSizeBadge
  import SanctumWeb.Components.HealthBadge
  import SanctumWeb.Components.StatBadge

  attr :id, :string, default: nil
  attr :side, :map, required: true, doc: "display map built by side_view/2"

  attr :size, :string,
    default: "md",
    values: ~w(md lg),
    doc: "art size: md = the pool grid tile; lg = 2x art, full-width on mobile (detail page)"

  attr :navigate, :string,
    default: nil,
    doc: "card detail path; when set, the art and name link to it"

  def card_side_tile(assigns) do
    assigns = assign(assigns, :lg?, assigns.size == "lg")

    ~H"""
    <div
      id={@id}
      class={[
        "mc-tile flex flex-col items-start border-2 border-neutral bg-base-200 shadow-comic sm:flex-row",
        (@lg? && "gap-6 p-5") || "gap-[13px] p-2"
      ]}
    >
      <.maybe_link
        navigate={@navigate}
        class={[
          "flex-none self-center border-2 border-neutral shadow-comic-sm sm:self-start",
          art_frame_class(@side.is_landscape, @size)
        ]}
      >
        <.mc_card
          name={@side.name}
          type={@side.type}
          cost={@side.cost}
          aspect={@side.aspect_key}
          image_url={@side.image_url}
          gradient_from={@side.gradient_from}
          gradient_to={@side.gradient_to}
          size={@size}
          show_cost={false}
        />
      </.maybe_link>

      <div class="flex min-w-0 flex-1 flex-col">
        <div class="h-12 flex items-start gap-3">
          <div
            :if={@side.show_cost}
            class="flex flex-none items-center justify-center rounded-full font-elektra-med text-4xl/normal"
          >
            {@side.cost}
          </div>
          <div class="min-w-0 flex-1">
            <div class={[
              "font-ibm-mono text-[9px] uppercase tracking-[0.2em]",
              @side.aspect_text_class
            ]}>
              {@side.type_name} · {@side.aspect_name}
            </div>
            <div class="mt-[3px] flex items-baseline gap-2">
              <div class="min-w-0 flex-1 font-anton text-[22px] uppercase leading-[0.94]">
                <.link :if={@navigate} navigate={@navigate} class="hover:text-primary">
                  {@side.name}
                </.link>
                <span :if={!@navigate}>{@side.name}</span>
              </div>
              <div
                :if={@side.stage_label}
                class="flex-none font-elektra-med text-[18px] leading-none text-white"
              >
                {@side.stage_label}
              </div>
            </div>
          </div>
        </div>

        <div :if={@side.is_ally} class="flex items-start gap-2 w-full">
          <div class="flex flex-grow items-start justify-start">
            <.stat_badge
              stat={:thw}
              value={@side.thwart}
              consequential={@side.thwart_consequential}
              size={64}
            />
            <.stat_badge
              stat={:atk}
              value={@side.attack}
              consequential={@side.attack_consequential}
              size={64}
            />
          </div>
          <div class="flex items-start justify-end">
            <.health_badge value={@side.health} size={52} />
          </div>
        </div>

        <div :if={@side.is_hero} class="flex items-start gap-2 w-full">
          <div class="flex flex-grow items-start justify-start">
            <.stat_badge stat={:thw} value={@side.thwart} size={64} hero={true} />
            <.stat_badge stat={:atk} value={@side.attack} size={64} hero={true} />
            <.stat_badge stat={:def} value={@side.defense} size={64} hero={true} />
          </div>
          <div class="flex items-start justify-end">
            <.health_badge value={@side.health} size={52} />
          </div>
        </div>

        <div :if={@side.is_villain or @side.is_minion} class="flex items-start gap-2 w-full">
          <div class="flex flex-grow items-start justify-start">
            <.stat_badge stat={:thw} value={@side.scheme} label="SCH" size={64} />
            <.stat_badge stat={:atk} value={@side.attack} star={@side.attack_star} size={64} />
          </div>
          <div :if={@side.health} class="flex items-start justify-end">
            <.health_badge value={@side.health} player={@side.health_per_player} size={52} />
          </div>
        </div>

        <div
          :if={@side.is_scheme and (@side.start_threat || @side.escalation_threat)}
          class="mb-1 w-full"
        >
          <div class="inline-flex -skew-x-[9deg] border-2 border-white bg-base-100 shadow-comic-sm">
            <.scheme_cell value={@side.start_threat} per_player={@side.start_threat_pp} />
            <div :if={@side.is_main_scheme} class="w-px self-stretch bg-white"></div>
            <.scheme_cell
              :if={@side.is_main_scheme}
              value={@side.escalation_threat}
              per_player={@side.escalation_threat_pp}
              sign
            />
            <div :if={@side.is_main_scheme} class="w-px self-stretch bg-white"></div>
            <.scheme_cell
              :if={@side.is_main_scheme}
              value={@side.threat_target}
              per_player={@side.threat_per_player}
            />
          </div>
        </div>

        <div class={["h-px bg-neutral", (@lg? && "my-4") || "my-2"]}></div>

        <div
          :if={@side.traits != ""}
          class={[
            "flex justify-center font-komika text-xs font-semibold uppercase tracking-[0.02em] text-base-content/75",
            (@lg? && "mb-2.5") || "mb-1"
          ]}
        >
          {@side.traits}
        </div>

        <div class="font-barlow text-[13.5px] leading-[1.5] text-base-content/85">
          {Sanctum.CardText.to_html(@side.text)}
        </div>

        <div
          :if={@side.flavor}
          class={[
            "text-center font-barlow italic text-xs text-base-content/65",
            (@lg? && "my-3.5") || "my-2"
          ]}
        >
          {Sanctum.CardText.to_html(@side.flavor)}
        </div>

        <div
          :if={@side.pips != [] or (@side.is_hero and @side.hand_size)}
          class={["flex items-center gap-1", (@lg? && "mt-4") || "mt-2.5"]}
        >
          <span
            :for={{color_class, glyph} <- @side.pips}
            class={["font-champions text-2xl leading-none", color_class]}
          >
            {glyph}
          </span>
          <.hand_size_badge
            :if={@side.is_hero and @side.hand_size}
            value={@side.hand_size}
            class="ml-auto text-base-content/75"
          />
        </div>
      </div>
    </div>
    """
  end

  # Art frame dimensions. "md" is the fixed pool-grid size; "lg" doubles it on
  # sm+ screens and stretches to the available width on mobile, with the card's
  # printed aspect ratio (5/7 portrait, 7/5 landscape) deriving the height.
  defp art_frame_class(true = _landscape, "lg"), do: "aspect-[7/5] w-full sm:w-[420px]"
  defp art_frame_class(_portrait, "lg"), do: "aspect-[5/7] w-full sm:w-[300px]"
  defp art_frame_class(true = _landscape, _md), do: "h-[150px] w-[210px]"
  defp art_frame_class(_portrait, _md), do: "h-[210px] w-[150px]"

  # A link when a destination is given, otherwise a plain div — so the art
  # frame keeps identical markup on pages that are already the destination.
  attr :navigate, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  defp maybe_link(%{navigate: nil} = assigns) do
    ~H"""
    <div class={@class}>{render_slot(@inner_block)}</div>
    """
  end

  defp maybe_link(assigns) do
    ~H"""
    <.link navigate={@navigate} class={@class}>{render_slot(@inner_block)}</.link>
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

  @doc """
  Builds the tile's display map for a single card face. `side` must have its
  `card` relationship loaded; `hero_colors` is the `set -> {from, to}` palette
  map from `Sanctum.Heroes.hero_color_map/0`.
  """
  def side_view(side, hero_colors) do
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
      card_id: card.id,
      name: side.name,
      type: side.type,
      is_landscape: landscape_type?(side.type),
      cost: side.cost,
      show_cost: side.type != :resource and not is_nil(side.cost),
      aspect_key: aspect_key,
      aspect_name: aspect_name(aspect_key, card.set),
      gradient_from: gradient_from,
      gradient_to: gradient_to,
      type_name: type_name(side.type),
      aspect_text_class: aspect_classes(aspect_key).text,
      resources: resources,
      pips: resource_pips(resources),
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
      _ -> fallback_gradient(set)
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
