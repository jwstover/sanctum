defmodule SanctumWeb.CardLive.Show do
  use SanctumWeb, :live_view

  require Ash.Query

  alias SanctumWeb.Components.Card, as: CardComponent

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:cards}>
      <.header>
        {@title}
        <:subtitle>
          <span class="font-ibm-mono text-[12px] uppercase tracking-[0.16em]">
            {@card.base_code}
          </span>
          · {length(@card.card_sides)} side{if length(@card.card_sides) != 1, do: "s"}
          <span :if={@card.is_multi_sided} class="text-base-content/45">· multi-sided</span>
        </:subtitle>

        <:actions>
          <.button navigate={~p"/admin/cards"}>
            <.icon name="hero-arrow-left" /> Back
          </.button>
          <.button variant="primary" navigate={~p"/admin/cards/#{@card}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit
          </.button>
        </:actions>
      </.header>

      <div class="space-y-5">
        <!-- card-level info -->
        <.panel class="p-4">
          <div class="mb-3 font-ibm-mono text-[10px] uppercase tracking-[0.2em] text-base-content/50">
            Card Info
          </div>
          <div class="grid grid-cols-2 gap-x-6 gap-y-3 sm:grid-cols-3 lg:grid-cols-4">
            <.meta label="Base Code" value={@card.base_code} />
            <.meta label="Primary Code" value={@card.code} />
            <.meta label="Set" value={@card.set} />
            <.meta label="Pack" value={@card.pack} />
            <.meta label="Deck Limit" value={@card.deck_limit} />
            <.meta label="Unique" value={yes_no(@card.unique)} />
            <.meta label="Permanent" value={yes_no(@card.permanent)} />
            <.meta label="Multi-sided" value={yes_no(@card.is_multi_sided)} />
          </div>
        </.panel>

        <!-- one panel per side -->
        <.panel :for={side <- @sides} class="flex flex-col gap-5 p-4 sm:flex-row sm:items-start">
          <div class="h-[330px] w-[236px] flex-none self-center border-2 border-neutral shadow-comic sm:self-start">
            <.mc_card
              name={side.name}
              cost={side.cost}
              type={side.type}
              aspect={side.aspect_key}
              resources={side.resources}
              image_url={side.image_url}
              gradient_from={side.gradient_from}
              gradient_to={side.gradient_to}
              size="lg"
              show_cost={false}
            />
          </div>

          <div class="flex min-w-0 flex-1 flex-col">
            <div class="flex flex-wrap items-center gap-2">
              <.badge :if={side.is_primary_side} aspect="protection">Primary</.badge>
              <.badge>Side {side.side_identifier}</.badge>
            </div>

            <div class={[
              "mt-2 font-ibm-mono text-[10px] uppercase tracking-[0.2em]",
              side.aspect_text_class
            ]}>
              {side.type_name}<span :if={side.aspect_name}> · {side.aspect_name}</span>
            </div>
            <h2 class="mt-1 font-anton text-[30px] uppercase leading-[0.92]">{side.name}</h2>
            <div :if={side.subname} class="font-barlow text-[14px] italic text-base-content/55">
              {side.subname}
            </div>

            <!-- resource pips -->
            <div :if={side.pips != []} class="mt-3 flex items-center gap-1.5">
              <span
                :for={{color_class, glyph} <- side.pips}
                class={["font-champions text-[18px] leading-none", color_class]}
              >
                {glyph}
              </span>
            </div>

            <div
              :if={side.traits != ""}
              class="mt-3 font-barlow-condensed text-[12px] font-semibold uppercase tracking-[0.02em] text-base-content/55"
            >
              {side.traits}
            </div>

            <div class="my-3 h-px bg-neutral"></div>

            <div :if={side.text} class="font-barlow text-[14px] leading-[1.55] text-base-content/85">
              {Sanctum.CardText.to_html(side.text)}
            </div>

            <!-- combat stats -->
            <div :if={side.stats != []} class="mt-4 grid grid-cols-2 gap-1.5 sm:grid-cols-4">
              <.stat_box :for={s <- side.stats} value={s.value} label={s.label} color={s.color} />
            </div>

            <!-- keyword icons -->
            <div :if={side.icons != []} class="mt-4 flex flex-wrap gap-1.5">
              <.badge :for={icon <- side.icons} aspect="hero">{icon}</.badge>
            </div>

            <!-- other typed stats -->
            <div :if={side.meta != []} class="mt-4 grid grid-cols-2 gap-x-6 gap-y-3 sm:grid-cols-3">
              <.meta :for={m <- side.meta} label={m.label} value={m.value} />
            </div>
          </div>
        </.panel>

        <!-- alternate printings -->
        <.panel :if={@alts != []} class="p-4">
          <div class="mb-3 font-ibm-mono text-[10px] uppercase tracking-[0.2em] text-base-content/50">
            Alternate Printings ({length(@alts)})
          </div>
          <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
            <figure :for={alt <- @alts} class="flex flex-col gap-1.5">
              <div class="aspect-[5/7] w-full overflow-hidden border-2 border-neutral shadow-comic">
                <img
                  src={alt.image_url}
                  alt={alt.code}
                  loading="lazy"
                  class="h-full w-full object-cover"
                />
              </div>
              <figcaption class="font-ibm-mono text-[10px] uppercase tracking-[0.16em] text-base-content/50">
                {alt.code}<span :if={alt.pack}> · {alt.pack}</span>
              </figcaption>
            </figure>
          </div>
        </.panel>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp meta(assigns) do
    ~H"""
    <div :if={present?(@value)}>
      <div class="font-ibm-mono text-[10px] uppercase tracking-[0.2em] text-base-content/45">
        {@label}
      </div>
      <div class="mt-0.5 font-barlow-condensed text-[15px] font-semibold">{@value}</div>
    </div>
    """
  end

  attr :value, :any, required: true
  attr :label, :string, required: true
  attr :color, :string, required: true

  defp stat_box(assigns) do
    ~H"""
    <div
      class="border-2 border-neutral bg-base-100 px-0.5 py-1.5 text-center"
      style={"border-top:3px solid #{@color};"}
    >
      <div class="font-anton text-[20px] leading-[0.9]">{@value}</div>
      <div class="mt-[3px] text-[8px] font-extrabold uppercase tracking-[0.12em] text-base-content/50">
        {@label}
      </div>
    </div>
    """
  end

  attr :aspect, :any, default: nil, doc: "aspect key for accent color; nil = neutral badge"
  slot :inner_block, required: true

  defp badge(assigns) do
    classes = assigns.aspect && CardComponent.aspect_classes(assigns.aspect)
    assigns = assign(assigns, :badge_classes, classes)

    ~H"""
    <span class={[
      "border-2 bg-black px-2 py-0.5 font-barlow-condensed text-[11px] font-bold uppercase tracking-[0.08em]",
      (@badge_classes && [@badge_classes.text, @badge_classes.border]) ||
        "border-neutral text-base-content/80"
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    card =
      Ash.get!(Sanctum.Games.Card, id,
        actor: socket.assigns[:current_user],
        load: [:card_sides, :primary_side, :alts]
      )

    gradient = hero_gradient(card.set)
    title = (card.primary_side && card.primary_side.name) || card.base_code

    sides =
      card.card_sides
      |> Enum.sort_by(& &1.side_identifier)
      |> Enum.map(&side_view(&1, gradient))

    # Alternate printings that have a mirrored scan to show.
    alts =
      card.alts
      |> Enum.filter(& &1.image_url)
      |> Enum.sort_by(& &1.code)
      |> Enum.map(&%{code: &1.code, pack: &1.pack, image_url: &1.image_url})

    {:ok,
     socket
     |> assign(:page_title, title)
     |> assign(:card, card)
     |> assign(:title, title)
     |> assign(:sides, sides)
     |> assign(:alts, alts)}
  end

  # Builds the display map for one card side.
  defp side_view(side, hero_gradient) do
    hero_face? = side.type in [:hero, :alter_ego]

    resources =
      [
        energy: side.resource_energy_count,
        mental: side.resource_mental_count,
        physical: side.resource_physical_count,
        wild: side.resource_wild_count
      ]
      |> Enum.flat_map(fn {res, n} -> List.duplicate(res, n || 0) end)

    {gradient_from, gradient_to} =
      if hero_face?, do: hero_gradient || {nil, nil}, else: {nil, nil}

    %{
      id: side.id,
      name: side.name,
      subname: side.subname,
      cost: side.cost,
      side_identifier: side.side_identifier,
      is_primary_side: side.is_primary_side,
      type: side.type,
      type_name: type_name(side.type),
      aspect_key: if(hero_face?, do: :hero, else: side.aspect || :basic),
      aspect_name: side.aspect && aspect_name(side.aspect),
      aspect_text_class:
        CardComponent.aspect_classes(if(hero_face?, do: :hero, else: side.aspect)).text,
      resources: resources,
      pips: CardComponent.resource_pips(resources),
      traits: format_traits(side.traits),
      text: side.text,
      image_url: side.image_url,
      gradient_from: gradient_from,
      gradient_to: gradient_to,
      stats: combat_stats(side),
      icons: keyword_icons(side),
      meta: typed_meta(side)
    }
  end

  defp combat_stats(side) do
    [
      {"THW", side.thwart, "var(--color-aspect-leadership)"},
      {"ATK", side.attack, "var(--color-aspect-hero)"},
      {"DEF", side.defense, "var(--color-stat-defense)"},
      {"HP", side.health, "var(--color-aspect-protection)"}
    ]
    |> Enum.filter(fn {_l, stat, _c} -> stat_value(stat) != nil end)
    |> Enum.map(fn {label, stat, color} ->
      %{label: label, value: stat_box_value(stat), color: color}
    end)
  end

  defp keyword_icons(side) do
    [
      {"Acceleration", side.acceleration_icon},
      {"Amplify", side.amplify_icon},
      {"Crisis", side.crisis_icon},
      {"Hazard", side.hazard_icon}
    ]
    |> Enum.filter(fn {_label, on?} -> on? end)
    |> Enum.map(&elem(&1, 0))
  end

  defp typed_meta(side) do
    [
      {"Cost", side.cost},
      {"Hand Size", side.hand_size},
      {"Recover", stat_meta(side.recover)},
      {"Stage", side.stage},
      {"Scheme", side.scheme},
      {"Health Scaling", scaling_label(side.health)},
      {"Base Threat", stat_meta(side.base_threat)},
      {"Escalation", stat_meta(side.escalation_threat)},
      {"Max Threat", stat_meta(side.max_threat)},
      {"Boost", side.boost},
      {"Boost Star", yes_if(side.boost_star)}
    ]
    |> Enum.filter(fn {_label, value} -> present?(value) end)
    |> Enum.map(fn {label, value} -> %{label: label, value: value} end)
  end

  # Stat helpers. `stat_box_value` is compact (number + ★); `stat_meta` also
  # carries the scaling suffix for the detail rows.
  defp stat_value(%{value: value}), do: value
  defp stat_value(_), do: nil

  defp stat_box_value(%{value: value, star: star}) when not is_nil(value),
    do: "#{value}#{if star, do: "★", else: ""}"

  defp stat_box_value(_), do: nil

  defp stat_meta(%{value: value, star: star, scaling: scaling}) when not is_nil(value),
    do: "#{value}#{if star, do: "★", else: ""}#{scaling_suffix(scaling)}"

  defp stat_meta(_), do: nil

  defp scaling_suffix(:per_player), do: " /player"
  defp scaling_suffix(:per_group), do: " /group"
  defp scaling_suffix(_), do: ""

  defp scaling_label(%{scaling: :per_player}), do: "Per player"
  defp scaling_label(%{scaling: :per_group}), do: "Per group"
  defp scaling_label(_), do: nil

  defp hero_gradient(nil), do: nil

  defp hero_gradient(set) do
    Sanctum.Heroes.Hero
    |> Ash.Query.filter(set == ^set)
    |> Ash.read!()
    |> List.first()
    |> case do
      %{primary_color: from, secondary_color: to} when is_binary(from) and is_binary(to) ->
        {from, to}

      _ ->
        nil
    end
  end

  defp format_traits(traits) when is_list(traits), do: Enum.join(traits, " · ")
  defp format_traits(_), do: ""

  defp aspect_name(:hero), do: "Hero"
  defp aspect_name(aspect), do: aspect |> to_string() |> String.capitalize()

  defp type_name(nil), do: "Card"
  defp type_name(type), do: type |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp yes_no(true), do: "Yes"
  defp yes_no(_), do: "No"

  defp yes_if(true), do: "Yes"
  defp yes_if(_), do: nil

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true
end
