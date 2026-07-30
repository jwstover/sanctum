defmodule SanctumWeb.Components.DeckCharts do
  @moduledoc """
  The four MarvelCDB deck charts — skill icons, cost curve, aspects, types —
  drawn in the comic-dossier theme with plain CSS boxes and inline SVG. No
  chart library: the panel these live in is 400px wide on the builder and the
  data is a handful of integers, so a JS charting dep would cost more than it
  buys.

  `stats/1` takes the same `DeckCards.card_view/2` maps both deck surfaces
  already build and returns the four datasets; `deck_charts/1` renders them.
  Everything is derived per render — there is no chart state.

  ## Semantics (ported from MarvelCDB's `app.deck_charts.js`)

  All four charts count the **draw deck**: every copy of every non-permanent
  card. The skill-icon columns stack each resource into icons printed on hero
  (signature) cards versus everything else, matching MarvelCDB's two-series
  column. Cost X (stored as `-1`) is excluded from the cost curve, and cards
  with no printed cost are excluded too.

  ## Color

  Resource and aspect bars wear the design system's `--color-res-*` /
  `--color-aspect-*` entity tokens. Those are fixed app-wide — a physical pip
  is the same red in the card text, the pip column, and this chart — so they
  are used as-is rather than re-derived for chart contrast. Card types have no
  such token, so the palette in `@types` is purpose-built,
  validated all-pairs colorblind-safe against the `bg-base-200` panel surface
  (worst pair ΔE 9.1 protan / 9.3 tritan, normal-vision 15.9).

  Every bar, point, and slice is **direct-labeled with its value**. That is
  deliberate rather than decorative: this panel gets heavy use on phones, where
  there is no hover, so a tooltip-only value would be unreadable for half the
  audience. Titles carry the long-form breakdown for pointer users.
  """

  use Phoenix.Component

  import SanctumWeb.CoreComponents, only: [panel: 1]

  alias SanctumWeb.Components.ChampionsIcons

  # MarvelCDB's column order: physical, mental, energy, wild.
  @resources [
    {:physical, "Physical", "var(--color-res-physical)"},
    {:mental, "Mental", "var(--color-res-mental)"},
    {:energy, "Energy", "var(--color-res-energy)"},
    {:wild, "Wild", "var(--color-res-wild)"}
  ]

  # Hero-signature icons stack under the resource color in a recessive grey.
  @hero_segment_color "color-mix(in srgb, var(--color-base-content) 34%, transparent)"

  # Aspect colors are the app-wide entity tokens; labels match the deck-page
  # aspect chips (`DeckCards.aspect_badges/1`).
  @aspects [
    {:hero, "Hero", "var(--color-aspect-hero)"},
    {:aggression, "Aggression", "var(--color-aspect-aggression)"},
    {:justice, "Justice", "var(--color-aspect-justice)"},
    {:leadership, "Leadership", "var(--color-aspect-leadership)"},
    {:protection, "Protection", "var(--color-aspect-protection)"},
    {:pool, "Pool", "var(--color-aspect-pool)"},
    {:basic, "Basic", "var(--color-aspect-basic)"}
  ]

  # Categorical palette for card types — see the moduledoc on how it was
  # validated. Hues track MarvelCDB's (allies blue-ish, events red, upgrades
  # green, resources gold) where the CVD checks allowed it.
  @types [
    {:ally, "Allies", "#009ea3"},
    {:event, "Events", "#b6545a"},
    {:support, "Supports", "#6e6eb9"},
    {:upgrade, "Upgrades", "#197700"},
    {:resource, "Resources", "#ab9028"},
    {:player_side_scheme, "Side Schemes", "#a01186"}
  ]

  @other_color "var(--color-aspect-basic)"

  @doc """
  Derives the chart datasets from `DeckCards.card_view/2` maps.

  Returns `%{total, resources, costs, aspects, types}`, where `total` is the
  draw-deck size (permanent cards excluded, copies counted). An empty deck
  yields `total: 0` and empty series, which `deck_charts/1` renders as nothing.
  """
  def stats(card_views) do
    draw = Enum.filter(card_views, &(&1.qty > 0 and not &1.permanent))

    %{
      total: Enum.sum_by(draw, & &1.qty),
      resources: resource_series(draw),
      costs: cost_series(draw),
      aspects: slices(draw, & &1.aspect_key, @aspects),
      types: slices(draw, & &1.type, @types)
    }
  end

  # Icons, not cards: a card printing two wild pips contributes two, times its
  # quantity. Split by whether the printing is a hero signature card.
  defp resource_series(draw) do
    Enum.map(@resources, fn {key, label, color} ->
      token = Atom.to_string(key)

      {hero, other} = Enum.reduce(draw, {0, 0}, &add_pips(&1, &2, token))

      %{key: key, token: token, label: label, color: color, hero: hero, other: other}
    end)
  end

  defp add_pips(view, {hero, other}, token) do
    count = view.qty * Enum.count(view.pips, &(&1 == token))
    if view.hero?, do: {hero + count, other}, else: {hero, other + count}
  end

  # A dense 0..max series so gaps in the curve read as gaps, not as a shortcut
  # between the costs either side of them.
  defp cost_series(draw) do
    counts =
      draw
      |> Enum.filter(&(is_integer(&1.cost_value) and &1.cost_value >= 0))
      |> Enum.reduce(%{}, fn view, acc ->
        Map.update(acc, view.cost_value, view.qty, &(&1 + view.qty))
      end)

    case Map.keys(counts) do
      [] -> []
      costs -> for cost <- 0..Enum.max(costs), do: %{cost: cost, count: counts[cost] || 0}
    end
  end

  # Donut slices for one dimension: the known keys first, in the canonical
  # order they're declared in, then anything else.
  #
  # That "anything else" bucket is load-bearing, not defensive. Aspects are
  # data-driven now (`Sanctum.Games.Aspect`), so a homebrew aspect is a key
  # this module has never heard of — and the donut's center prints the deck
  # total, so a silently dropped key would make the slices stop summing to it.
  # Unknowns get the neutral grey; interpolating `--color-aspect-<key>` for
  # them would emit a var that doesn't exist and paint nothing.
  defp slices(draw, key_fun, known) do
    counts = tally(draw, key_fun)
    known_keys = Enum.map(known, fn {key, _label, _color} -> Atom.to_string(key) end)

    declared =
      for {key, label, color} <- known, count = counts[Atom.to_string(key)] do
        %{key: key, label: label, color: color, count: count}
      end

    other =
      for {key, count} <- counts, key not in known_keys do
        %{key: key, label: Phoenix.Naming.humanize(key), color: @other_color, count: count}
      end

    declared ++ Enum.sort_by(other, & &1.label)
  end

  # Aspect and type keys arrive as atoms from some loads and strings from
  # others (the Ash enums cast either way), so every tally key is stringified.
  defp tally(draw, key_fun) do
    Enum.reduce(draw, %{}, fn view, acc ->
      Map.update(acc, to_string(key_fun.(view)), view.qty, &(&1 + view.qty))
    end)
  end

  @doc """
  Renders the four charts as their own "Deck Stats" panel — a sibling of the
  decklist rather than a section inside it.

  Renders nothing for an empty draw deck. `stats` is the map from `stats/1`.
  """
  attr :stats, :map, required: true
  attr :class, :string, default: nil

  def deck_charts(assigns) do
    ~H"""
    <.panel :if={@stats.total > 0} class={String.trim("p-4 #{@class}")}>
      <div class="mb-4 flex items-baseline gap-2">
        <div class="font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/50">
          Deck Stats
        </div>
        <div class="font-barlow-condensed text-xs font-bold uppercase tracking-[0.08em] text-base-content/35">
          draw deck · {@stats.total} cards
        </div>
      </div>

      <div class="flex flex-col gap-5">
        <.chart title="Card Skill Icons" subtitle="Hero-card icons shaded">
          <.column_plot bars={resource_bars(@stats.resources)}>
            <:label :let={bar}>
              <ChampionsIcons.champions_icon token={bar.token} class="text-base" />
            </:label>
          </.column_plot>
          <div class="mt-2 flex items-center gap-1.5">
            <span
              class="size-2.5 flex-none border border-neutral"
              style={"background:#{hero_segment_color()}"}
            ></span>
            <span class="font-barlow-condensed text-xs font-bold uppercase tracking-[0.08em] text-base-content/45">
              From hero cards
            </span>
          </div>
        </.chart>

        <.chart title="Card Cost" subtitle="Cost X ignored">
          <.cost_chart points={@stats.costs} />
        </.chart>

        <.chart title="Card Aspects">
          <.donut slices={@stats.aspects} total={@stats.total} label="Card aspects" />
        </.chart>

        <.chart title="Card Types">
          <.donut slices={@stats.types} total={@stats.total} label="Card types" />
        </.chart>
      </div>
    </.panel>
    """
  end

  # Exposed to the template above; the swatch has to match the stacked segment.
  defp hero_segment_color, do: @hero_segment_color

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :inner_block, required: true

  defp chart(assigns) do
    ~H"""
    <div>
      <div class="font-anton text-sm uppercase tracking-[0.05em] text-base-content/85">
        {@title}
      </div>
      <div
        :if={@subtitle}
        class="font-ibm-mono text-[10px] uppercase tracking-[0.12em] text-base-content/40"
      >
        {@subtitle}
      </div>
      <div class="mt-2.5">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  defp resource_bars(resources) do
    Enum.map(resources, fn res ->
      %{
        token: res.token,
        label: res.label,
        total: res.hero + res.other,
        # Top-down, mirroring MarvelCDB's reversed stack: non-hero above hero.
        segments: [
          %{value: res.other, color: res.color},
          %{value: res.hero, color: @hero_segment_color}
        ],
        title: resource_title(res)
      }
    end)
  end

  defp resource_title(%{label: label, hero: 0, other: other}), do: "#{label}: #{other}"

  defp resource_title(%{label: label, hero: hero, other: other}),
    do: "#{label}: #{hero + other} (#{other} on other cards, #{hero} on hero cards)"

  # A stacked column plot in three aligned rows — values, bars, labels — so the
  # baseline can be one unbroken rule across the whole plot instead of a
  # per-column border broken by the gutters.
  attr :bars, :list, required: true
  slot :label, required: true

  defp column_plot(assigns) do
    assigns =
      assign(assigns, :max, assigns.bars |> Enum.map(& &1.total) |> Enum.max(&>=/2, fn -> 0 end))

    ~H"""
    <div :if={@bars != []}>
      <div class="flex gap-1.5">
        <div
          :for={bar <- @bars}
          class="min-w-0 flex-1 text-center font-anton text-xs leading-none text-base-content/70"
        >
          {bar.total}
        </div>
      </div>

      <div class="mt-1 flex h-[84px] items-end gap-1.5 border-b-2 border-neutral">
        <div
          :for={bar <- @bars}
          title={bar.title}
          class="flex h-full min-w-0 flex-1 items-end justify-center"
        >
          <div
            class="flex w-full max-w-[56px] flex-col gap-[2px]"
            style={"height:#{bar_height(bar.total, @max)}%"}
          >
            <div
              :for={segment <- Enum.filter(bar.segments, &(&1.value > 0))}
              class="min-h-[3px]"
              style={"flex:#{segment.value} 1 0;background:#{segment.color}"}
            >
            </div>
          </div>
        </div>
      </div>

      <div class="mt-1.5 flex gap-1.5">
        <div :for={bar <- @bars} title={bar.title} class="min-w-0 flex-1 text-center leading-none">
          {render_slot(@label, bar)}
        </div>
      </div>
    </div>
    """
  end

  defp bar_height(_total, 0), do: 0
  defp bar_height(total, max), do: Float.round(total / max * 100, 2)

  # Cost curve. Geometry is in percentages of the plot box, and the SVG holds
  # *only* the curve — it stretches to the box with preserveAspectRatio="none"
  # so one 0–100 coordinate space drives both the SVG points and the HTML
  # markers/labels placed on top with `left`/`top` percentages.
  #
  # Text and markers are HTML, not SVG, for a reason: a scaled viewBox scales
  # its own `font-size` too, so SVG text renders at a different pixel size on
  # every panel width and can't match the column charts' type. In HTML they
  # wear the same Tailwind classes as every other chart here. `vector-effect`
  # keeps the stroke at a true 2px despite the non-uniform scale.
  @cost_pad_x 4.0
  @cost_curve_top 22.0
  @cost_baseline 94.0

  attr :points, :list, required: true

  defp cost_chart(assigns) do
    assigns = assign(assigns, :plot, cost_plot(assigns.points))

    ~H"""
    <p :if={@points == []} class="font-barlow-condensed text-sm italic text-base-content/45">
      No cards with a printed cost.
    </p>

    <div :if={@points != []}>
      <div class="relative h-[104px]">
        <svg
          viewBox="0 0 100 100"
          preserveAspectRatio="none"
          class="absolute inset-0 size-full"
          role="img"
          aria-label={"Card cost curve: #{@plot.summary}"}
        >
          <polygon
            points={@plot.area}
            fill="color-mix(in srgb, var(--color-primary) 9%, transparent)"
          />
          <polyline
            points={@plot.line}
            fill="none"
            stroke="var(--color-primary)"
            stroke-width="2"
            stroke-linejoin="round"
            vector-effect="non-scaling-stroke"
          />
          <line
            x1={@plot.pad_x}
            y1={@plot.baseline}
            x2={100 - @plot.pad_x}
            y2={@plot.baseline}
            stroke="var(--color-neutral)"
            stroke-width="2"
            vector-effect="non-scaling-stroke"
          />
        </svg>

        <span
          :for={point <- @plot.points}
          title={"Cost #{point.cost}: #{point.count} cards"}
          class="absolute size-2.5 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-primary bg-base-200"
          style={"left:#{point.x}%;top:#{point.y}%"}
        ></span>
        <span
          :for={point <- @plot.points}
          :if={point.count > 0}
          class="absolute -translate-x-1/2 -translate-y-full pb-1.5 font-anton text-xs leading-none text-base-content/70"
          style={"left:#{point.x}%;top:#{point.y}%"}
        >
          {point.count}
        </span>
      </div>

      <div class="relative mt-0.5 h-3">
        <span
          :for={point <- @plot.points}
          class="absolute -translate-x-1/2 font-ibm-mono text-[11px] leading-none text-base-content/45"
          style={"left:#{point.x}%"}
        >
          {point.cost}
        </span>
      </div>
    </div>
    """
  end

  @cost_geometry %{pad_x: @cost_pad_x, baseline: @cost_baseline}

  defp cost_plot([]),
    do: Map.merge(@cost_geometry, %{points: [], line: nil, area: nil, summary: ""})

  defp cost_plot(costs) do
    max = costs |> Enum.map(& &1.count) |> Enum.max()
    span = 100 - 2 * @cost_pad_x
    last = length(costs) - 1
    height = @cost_baseline - @cost_curve_top

    points =
      costs
      |> Enum.with_index()
      |> Enum.map(fn {%{cost: cost, count: count}, index} ->
        x = if last == 0, do: 50.0, else: @cost_pad_x + index * span / last
        y = @cost_baseline - count / max * height
        %{cost: cost, count: count, x: Float.round(x, 2), y: Float.round(y, 2)}
      end)

    line = Enum.map_join(points, " ", &"#{&1.x},#{&1.y}")
    first = List.first(points)
    tail = List.last(points)

    Map.merge(@cost_geometry, %{
      points: points,
      line: line,
      area: "#{first.x},#{@cost_baseline} #{line} #{tail.x},#{@cost_baseline}",
      summary: Enum.map_join(points, ", ", &"cost #{&1.cost}: #{&1.count}")
    })
  end

  # A part-of-whole split (aspects, types) as a donut with a labeled legend
  # beside it. Slice arcs are drawn as dashed strokes on one circle so the 2px
  # surface gaps between segments come free from the dash gap.
  @donut_radius 38
  # Wider than the 2px a surface gap normally needs: the aspect donut can put
  # hero (#ce1b2e) right next to aggression (#b12020), and those two entity
  # tokens are near-identical reds. The seam has to be unmistakable on its own.
  @donut_gap 4

  attr :slices, :list, required: true
  attr :total, :integer, required: true
  attr :label, :string, required: true, doc: "what the split is over, for the a11y label"

  defp donut(assigns) do
    assigns =
      assigns
      |> assign(:arcs, donut_arcs(assigns.slices))
      |> assign(:radius, @donut_radius)

    ~H"""
    <div class="flex items-center gap-5">
      <svg
        viewBox="0 0 100 100"
        class="aspect-square w-1/3 min-w-[104px] max-w-[176px] flex-none"
        role="img"
        aria-label={"#{@label}: #{Enum.map_join(@slices, ", ", &"#{&1.label} #{&1.count}")}"}
      >
        <!-- SVG hit-testing honors the dash pattern, so each circle is only
             hoverable where its own arc is actually painted. -->
        <g transform="rotate(-90 50 50)">
          <circle
            :for={arc <- @arcs}
            cx="50"
            cy="50"
            r={@radius}
            fill="none"
            stroke={arc.slice.color}
            stroke-width="16"
            stroke-dasharray={"#{arc.length} #{arc.gap_length}"}
            stroke-dashoffset={arc.offset}
          >
            <title>{slice_title(arc.slice, @total)}</title>
          </circle>
        </g>
        <text
          x="50"
          y="53"
          text-anchor="middle"
          font-size="19"
          font-family="Anton, sans-serif"
          fill="var(--color-base-content)"
        >
          {@total}
        </text>
        <text
          x="50"
          y="64"
          text-anchor="middle"
          font-size="8"
          font-family="'Barlow Condensed', sans-serif"
          letter-spacing="1"
          fill="color-mix(in srgb, var(--color-base-content) 45%, transparent)"
        >
          CARDS
        </text>
      </svg>

      <!-- Capped so the right-aligned numbers can't strand a long way from the
           label they belong to on a wide panel. The share column earns the
           slack that's left: it's the thing a part-of-whole chart is actually
           saying, and reading it off the arcs is guesswork. -->
      <ul class="flex min-w-0 max-w-[18rem] flex-1 flex-col gap-1.5">
        <!-- Same tooltip as the arc: the row is a far bigger hover target, and
             on a narrow panel it's the only one that isn't fiddly. -->
        <li
          :for={slice <- @slices}
          title={slice_title(slice, @total)}
          class="flex items-baseline gap-2"
        >
          <span
            class="size-2.5 flex-none self-center border border-neutral"
            style={"background:#{slice.color}"}
          ></span>
          <span class="min-w-0 flex-1 truncate font-barlow-condensed text-sm font-semibold text-base-content/80">
            {slice.label}
          </span>
          <span class="flex-none font-ibm-mono text-xs text-base-content/70">
            {slice.count}
          </span>
          <span class="w-9 flex-none text-right font-ibm-mono text-xs text-base-content/40">
            {share(slice.count, @total)}%
          </span>
        </li>
      </ul>
    </div>
    """
  end

  defp share(_count, 0), do: 0
  defp share(count, total), do: round(count / total * 100)

  defp slice_title(%{label: label, count: count}, total),
    do: "#{label}: #{count} cards (#{share(count, total)}%)"

  # dasharray/dashoffset arcs around one circumference. A lone slice draws as a
  # closed ring — a gap there would read as a missing segment, not a divider.
  defp donut_arcs([]), do: []

  defp donut_arcs([slice]) do
    circumference = 2 * :math.pi() * @donut_radius
    [%{slice: slice, length: round_2(circumference), gap_length: 0, offset: 0}]
  end

  defp donut_arcs(slices) do
    circumference = 2 * :math.pi() * @donut_radius
    total = Enum.sum_by(slices, & &1.count)

    {arcs, _} =
      Enum.map_reduce(slices, 0.0, fn slice, start ->
        span = slice.count / total * circumference
        length = max(span - @donut_gap, 1.0)

        arc = %{
          slice: slice,
          length: round_2(length),
          gap_length: round_2(circumference - length),
          offset: round_2(-start)
        }

        {arc, start + span}
      end)

    arcs
  end

  defp round_2(value), do: Float.round(value * 1.0, 2)
end
