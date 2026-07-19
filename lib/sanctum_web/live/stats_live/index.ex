defmodule SanctumWeb.StatsLive.Index do
  @moduledoc """
  Public "Vault Stats" page — deck-collection rollups (growth over time,
  decks per hero, aspect splits) rendered as ECharts via the `Chart` hook.
  Every chart has a data-table twin so no value is gated behind the canvas.
  """
  use SanctumWeb, :live_view

  on_mount {SanctumWeb.LiveUserAuth, :live_user_optional}

  alias Sanctum.Decks.Stats
  alias SanctumWeb.Components.Card, as: CardComponent

  # Design tokens (assets/css/app.css) the chart options reference directly —
  # ECharts renders to canvas, so CSS variables can't reach it.
  @gold "#dbcb36"
  @surface "#15151a"
  @muted "rgba(244, 241, 234, 0.55)"
  @hairline "#2a2a30"

  # Chart-local variants of the aspect tokens, snapped into the dataviz
  # dark-mode band (OKLCH L 0.48–0.67, C ≥ 0.10) and validated against the
  # base-200 surface: adjacent-pair CVD ΔE ≥ 8 and normal-vision ΔE ≥ 15 in
  # this display order. "Basic" is deliberately the de-emphasis gray — every
  # bar's identity is carried by its axis label, never color alone.
  @aspect_colors [
    {"aggression", "Aggression", "#b21f26"},
    {"justice", "Justice", "#a59318"},
    {"leadership", "Leadership", "#2fa4af"},
    {"protection", "Protection", "#4c9800"},
    {"pool", "Pool", "#cd6e9d"},
    {"basic", "Basic", "#5c5b66"}
  ]

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :hero_panel,
        assigns.stats && hero_panel_view(assigns.stats, assigns.hero_drill, assigns.aspect_drill)
      )

    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:stats}>
      <.header>
        Vault Stats
        <:subtitle>
          The deck vault by the numbers — growth over time, hero popularity, and aspect splits.
        </:subtitle>
      </.header>

      <div :if={@stats == nil} class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
        <div :for={_ <- 1..6} class="h-20 animate-pulse border-[3px] border-neutral bg-base-300" />
      </div>

      <div :if={@stats != nil} class="flex flex-col gap-6">
        <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
          <.stat_tile label="Decks" value={@stats.totals.decks} color="text-primary" />
          <.stat_tile label="Unique cards" value={@stats.totals.cards} color="text-secondary" />
          <.stat_tile label="Heroes" value={@stats.totals.heroes} color="text-aspect-hero" />
          <.stat_tile
            label="Villains"
            value={@stats.totals.villains}
            color="text-aspect-encounter"
          />
          <.stat_tile
            label="Added this month"
            value={@stats.totals.this_month}
            color="text-success"
          />
          <.text_tile label="Most built hero" value={top_hero_name(@stats.per_hero)} />
        </div>

        <.chart_panel
          :if={@stats.totals.decks > 0}
          id="decks-by-month"
          title="Decks added over time"
          subtitle="New decks per month, by their MarvelCDB publish date."
          option={by_month_option(@stats.by_month)}
          height="320px"
        >
          <:table_head>
            <th class="pr-6 text-left">Month</th>
            <th class="text-right">Decks</th>
          </:table_head>
          <tr :for={{month, count} <- Enum.reverse(@stats.by_month)}>
            <td class="pr-6">{Calendar.strftime(month, "%b %Y")}</td>
            <td class="text-right tabular-nums">{count}</td>
          </tr>
        </.chart_panel>

        <.chart_panel
          :if={@stats.totals.decks > 0}
          id="decks-per-hero"
          title={@hero_panel.title}
          subtitle={@hero_panel.subtitle}
          option={@hero_panel.option}
          height={@hero_panel.height}
          click_event={@hero_panel.click_event}
        >
          <:action :if={@hero_panel.back}>
            <.button phx-click="drill_back">
              <.icon name="hero-arrow-left" class="size-4" /> {@hero_panel.back}
            </.button>
          </:action>
          <:table_head>
            <th class="pr-6 text-left">{@hero_panel.col}</th>
            <th class="text-right">Decks</th>
          </:table_head>
          <tr :for={{label, count} <- @hero_panel.rows}>
            <td class="pr-6">{label}</td>
            <td class="text-right tabular-nums">{count}</td>
          </tr>
        </.chart_panel>

        <.chart_panel
          :if={@stats.totals.decks > 0}
          id="decks-by-aspect"
          title="Decks by aspect"
          subtitle="Multi-aspect decks count once under each aspect; basic decks run no aspect."
          option={by_aspect_option(@stats.by_aspect)}
          height="288px"
        >
          <:table_head>
            <th class="pr-6 text-left">Aspect</th>
            <th class="text-right">Decks</th>
          </:table_head>
          <tr :for={{aspect, count} <- @stats.by_aspect}>
            <td class="pr-6">{aspect_label(aspect)}</td>
            <td class="text-right tabular-nums">{count}</td>
          </tr>
        </.chart_panel>

        <.panel :if={@stats.totals.decks == 0} class="p-8 text-center">
          <p class="font-anton text-lg uppercase tracking-[0.05em] text-base-content/60">
            No decks in the vault yet
          </p>
        </.panel>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :option, :map, required: true
  attr :height, :string, required: true
  attr :click_event, :string, default: nil
  slot :action
  slot :table_head, required: true
  slot :inner_block, required: true

  defp chart_panel(assigns) do
    ~H"""
    <.panel class="p-4 sm:p-5">
      <div class="flex items-start justify-between gap-3">
        <div>
          <h2 class="font-anton text-lg uppercase tracking-[0.05em]">{@title}</h2>
          <p class="mb-3 font-barlow-condensed text-sm text-base-content/55">{@subtitle}</p>
        </div>
        {render_slot(@action)}
      </div>
      <div
        id={"#{@id}-chart"}
        phx-hook="Chart"
        phx-update="ignore"
        data-option={Jason.encode!(@option)}
        data-click-event={@click_event}
        data-height={@height}
        class="w-full"
        style={"height: #{@height}"}
        role="img"
        aria-label={"#{@title} chart — the same data is in the table below."}
      >
      </div>
      <details class="mt-3">
        <summary class="cursor-pointer font-ibm-mono text-[11px] uppercase tracking-[0.15em] text-base-content/55">
          View data
        </summary>
        <div class="mt-2 max-h-64 overflow-y-auto">
          <table class="font-barlow-condensed text-sm">
            <thead>
              <tr class="font-ibm-mono text-[11px] uppercase tracking-[0.15em] text-base-content/55">
                {render_slot(@table_head)}
              </tr>
            </thead>
            <tbody>
              {render_slot(@inner_block)}
            </tbody>
          </table>
        </div>
      </details>
    </.panel>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :color, :string, default: "text-primary"

  defp stat_tile(assigns) do
    ~H"""
    <div class="border-[3px] border-neutral bg-base-300 px-4 py-3">
      <div class={["font-bangers text-3xl leading-none", @color]}>{format_count(@value)}</div>
      <div class="mt-1 font-ibm-mono text-[11px] uppercase tracking-[0.15em] text-base-content/55">
        {@label}
      </div>
    </div>
    """
  end

  # 51461 → "51,461"
  defp format_count(n) do
    n
    |> Integer.to_string()
    |> String.replace(~r/(?<=\d)(?=(\d{3})+$)/, ",")
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp text_tile(assigns) do
    ~H"""
    <div class="border-[3px] border-neutral bg-base-300 px-4 py-3">
      <div class="truncate font-barlow-condensed text-xl font-bold leading-none text-primary">
        {@value}
      </div>
      <div class="mt-1 font-ibm-mono text-[11px] uppercase tracking-[0.15em] text-base-content/55">
        {@label}
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        page_title: "Vault Stats",
        stats: nil,
        hero_drill: nil,
        aspect_drill: nil
      )

    # Defer the rollup queries past the static render so the shell paints
    # immediately (same pattern as the admin health snapshot).
    socket =
      if connected?(socket), do: start_async(socket, :load_stats, &load_stats/0), else: socket

    {:ok, socket}
  end

  @impl true
  def handle_event("hero_bar_clicked", %{"heroId" => hero_id, "name" => name}, socket) do
    case Ecto.UUID.cast(hero_id) do
      {:ok, id} ->
        {:noreply,
         assign(socket,
           hero_drill: %{id: id, name: name, rows: Stats.by_aspect(id)},
           aspect_drill: nil
         )}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("aspect_bar_clicked", %{"aspect" => key}, socket) do
    hero = socket.assigns.hero_drill

    if hero && List.keymember?(@aspect_colors, key, 0) do
      {:noreply, assign(socket, :aspect_drill, %{key: key, rows: Stats.top_cards(hero.id, key)})}
    else
      {:noreply, socket}
    end
  end

  # Pops one drill level: top cards → aspect split → all heroes.
  def handle_event("drill_back", _params, socket) do
    if socket.assigns.aspect_drill do
      {:noreply, assign(socket, :aspect_drill, nil)}
    else
      {:noreply, assign(socket, :hero_drill, nil)}
    end
  end

  @impl true
  def handle_async(:load_stats, {:ok, stats}, socket) do
    {:noreply, assign(socket, :stats, stats)}
  end

  def handle_async(:load_stats, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:stats, %{
       totals: %{decks: 0, heroes: 0, this_month: 0},
       by_month: [],
       per_hero: [],
       by_aspect: []
     })
     |> put_flash(:error, "Stats failed to load: #{inspect(reason)}")}
  end

  defp load_stats do
    %{
      totals: Stats.totals(),
      by_month: Stats.by_month(),
      per_hero: Stats.per_hero(),
      by_aspect: Stats.by_aspect()
    }
  end

  defp top_hero_name([%{name: name} | _]), do: name
  defp top_hero_name([]), do: "—"

  # Everything the hero drill-down panel needs for its current level:
  # all heroes → one hero's aspect split → one aspect's most-used cards.
  # `rows` is normalized to `{label, count}` for the shared table twin.
  defp hero_panel_view(stats, nil = _hero_drill, _aspect_drill) do
    %{
      title: "Decks per hero",
      subtitle:
        "Every hero with a deck in the vault — all #{length(stats.per_hero)} of them, each bar in the hero's own colors. Click a bar for that hero's aspect split.",
      option: per_hero_option(stats.per_hero),
      height: "#{length(stats.per_hero) * 24 + 70}px",
      click_event: "hero_bar_clicked",
      back: nil,
      col: "Hero",
      rows: Enum.map(stats.per_hero, &{&1.name, &1.count})
    }
  end

  defp hero_panel_view(_stats, hero, nil = _aspect_drill) do
    %{
      title: "#{hero.name} — decks by aspect",
      subtitle:
        "How #{hero.name}'s decks split across aspects. Click a bar for the aspect's most-used cards.",
      option: by_aspect_option(hero.rows, drill_from: hero.id, clickable: true),
      height: "260px",
      click_event: "aspect_bar_clicked",
      back: "All heroes",
      col: "Aspect",
      rows: Enum.map(hero.rows, fn {key, count} -> {aspect_label(key), count} end)
    }
  end

  defp hero_panel_view(_stats, hero, aspect) do
    label = aspect_label(aspect.key)

    subtitle =
      if aspect.key == "basic",
        do: "The basic cards appearing in the most of #{hero.name}'s aspect-less decks.",
        else: "The #{label} cards appearing in the most of #{hero.name}'s #{label} decks."

    %{
      title: "#{hero.name} — top #{label} cards",
      subtitle: subtitle,
      option: top_cards_option(aspect.rows, aspect.key),
      height: "#{max(length(aspect.rows), 1) * 30 + 70}px",
      click_event: nil,
      back: "#{hero.name} aspects",
      col: "Card",
      rows: aspect.rows
    }
  end

  defp aspect_label(key) do
    {_, label, _} = List.keyfind!(@aspect_colors, key, 0)
    label
  end

  defp aspect_color(key) do
    {_, _, color} = List.keyfind!(@aspect_colors, key, 0)
    color
  end

  # ── ECharts options ──────────────────────────────────────────────────────
  # Chrome (axis hairlines, text, tooltip surface) lives in the hook's
  # registered theme; these carry data and per-chart geometry.

  defp by_month_option(rows) do
    %{
      grid: %{left: 8, right: 16, top: 16, bottom: 8},
      tooltip: %{trigger: "axis", axisPointer: %{type: "line", lineStyle: %{color: @hairline}}},
      xAxis: %{type: "time"},
      yAxis: %{type: "value", minInterval: 1},
      series: [
        %{
          name: "Decks added",
          type: "line",
          data: Enum.map(rows, fn {month, count} -> [Date.to_iso8601(month), count] end),
          lineStyle: %{width: 2, color: @gold, cap: "round", join: "round"},
          # 8px marker with a 2px surface ring, shown on hover/emphasis.
          symbol: "circle",
          symbolSize: 8,
          showSymbol: false,
          itemStyle: %{color: @gold, borderColor: @surface, borderWidth: 2},
          areaStyle: %{color: @gold, opacity: 0.1}
        }
      ]
    }
  end

  defp per_hero_option(rows) do
    # ECharts category axes run bottom-up; reverse so rank 1 sits on top.
    rows = Enum.reverse(rows)

    %{
      grid: %{left: 8, right: 40, top: 8, bottom: 8},
      tooltip: %{trigger: "item"},
      xAxis: %{type: "value", minInterval: 1},
      yAxis: %{
        type: "category",
        data: Enum.map(rows, & &1.name),
        # Never skip hero names — the axis label is each bar's identity.
        axisLabel: %{interval: 0}
      },
      series: [
        %{
          # A stable series id + universalTransition lets ECharts morph this
          # chart into the per-hero aspect drill-down (and back) instead of
          # redrawing from scratch.
          id: "decks",
          name: "Decks",
          type: "bar",
          universalTransition: %{enabled: true, divideShape: "clone"},
          data:
            Enum.map(rows, fn row ->
              {from, to} = hero_gradient(row)

              %{
                value: row.count,
                # groupId ties each bar to its drill-down series; drill is
                # our own payload, pushed back on click by the Chart hook.
                groupId: row.id,
                drill: %{heroId: row.id},
                itemStyle: %{
                  color: %{
                    type: "linear",
                    x: 0,
                    y: 0,
                    x2: 1,
                    y2: 0,
                    colorStops: [
                      %{offset: 0, color: from},
                      %{offset: 1, color: to}
                    ]
                  }
                }
              }
            end),
          barWidth: 14,
          itemStyle: %{borderRadius: [0, 4, 4, 0]},
          label: %{show: true, position: "right", color: @muted, fontSize: 12}
        }
      ]
    }
  end

  # The hero's brand gradient (the deck browser's convention), with each hex
  # endpoint lightened until it clears a minimum contrast against the panel —
  # several heroes' palettes are near-black (Black Widow: #140b09) and would
  # otherwise paint an invisible bar. hsl() fallback gradients are already
  # mid-lightness and pass through untouched.
  defp hero_gradient(%{primary: from, secondary: to})
       when is_binary(from) and is_binary(to) do
    {visible_on_surface(from), visible_on_surface(to)}
  end

  defp hero_gradient(%{set: set}), do: CardComponent.fallback_gradient(set)

  @min_bar_contrast 1.8

  defp visible_on_surface(<<"#", _::binary-size(6)>> = hex) do
    if contrast_vs_surface(hex) >= @min_bar_contrast do
      hex
    else
      hex |> lighten(0.12) |> visible_on_surface()
    end
  end

  defp visible_on_surface(_other), do: @gold

  defp contrast_vs_surface(hex) do
    {l1, l2} = {rel_luminance(hex), rel_luminance(@surface)}
    (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
  end

  defp rel_luminance(hex) do
    [r, g, b] =
      hex
      |> rgb()
      |> Enum.map(fn c ->
        v = c / 255
        if v <= 0.04045, do: v / 12.92, else: ((v + 0.055) / 1.055) ** 2.4
      end)

    0.2126 * r + 0.7152 * g + 0.0722 * b
  end

  defp lighten(hex, amount) do
    [r, g, b] = hex |> rgb() |> Enum.map(&round(&1 + (255 - &1) * amount))
    "#" <> Base.encode16(<<r, g, b>>, case: :lower)
  end

  defp rgb(<<"#", r::binary-2, g::binary-2, b::binary-2>>) do
    Enum.map([r, g, b], &String.to_integer(&1, 16))
  end

  defp by_aspect_option(rows, opts \\ []) do
    rows = Enum.reverse(rows)
    drill_from = Keyword.get(opts, :drill_from)

    clickable = Keyword.get(opts, :clickable, false)

    series = %{
      id: "decks",
      name: "Decks",
      type: "bar",
      universalTransition: %{enabled: true, divideShape: "clone"},
      data:
        Enum.map(rows, fn {key, count} ->
          base = %{value: count, itemStyle: %{color: aspect_color(key)}}

          # groupId ties each aspect bar to the top-cards series it morphs
          # into; drill is the click payload the Chart hook pushes back.
          if clickable,
            do: Map.merge(base, %{groupId: key, drill: %{aspect: key}}),
            else: base
        end),
      barWidth: 16,
      itemStyle: %{borderRadius: [0, 4, 4, 0]},
      label: %{show: true, position: "right", color: @muted, fontSize: 12}
    }

    # As a drill-down, tie the series back to the hero bar it came from so
    # the morph animation splits/merges the right mark. Bars only advertise
    # clickability (pointer cursor) when they actually drill somewhere.
    series = if drill_from, do: Map.put(series, :dataGroupId, drill_from), else: series
    series = if clickable, do: series, else: Map.put(series, :cursor, "default")

    %{
      grid: %{left: 8, right: 40, top: 8, bottom: 8},
      tooltip: %{trigger: "item"},
      xAxis: %{type: "value", minInterval: 1},
      yAxis: %{type: "category", data: Enum.map(rows, fn {key, _} -> aspect_label(key) end)},
      series: [series]
    }
  end

  defp top_cards_option(rows, aspect_key) do
    rows = Enum.reverse(rows)

    %{
      grid: %{left: 8, right: 40, top: 8, bottom: 8},
      tooltip: %{trigger: "item"},
      xAxis: %{type: "value", minInterval: 1},
      yAxis: %{
        type: "category",
        data: Enum.map(rows, &elem(&1, 0)),
        axisLabel: %{interval: 0}
      },
      series: [
        %{
          id: "decks",
          name: "Decks",
          type: "bar",
          universalTransition: %{enabled: true, divideShape: "clone"},
          # Morph out of (and back into) the aspect bar that was clicked.
          dataGroupId: aspect_key,
          cursor: "default",
          data: Enum.map(rows, &elem(&1, 1)),
          barWidth: 16,
          itemStyle: %{color: aspect_color(aspect_key), borderRadius: [0, 4, 4, 0]},
          label: %{show: true, position: "right", color: @muted, fontSize: 12}
        }
      ]
    }
  end
end
