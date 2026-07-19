defmodule SanctumWeb.StatsLive.Index do
  @moduledoc """
  Public "Vault Stats" page — deck-collection rollups (growth over time,
  decks per hero, aspect splits) rendered as ECharts via the `Chart` hook.
  Every chart has a data-table twin so no value is gated behind the canvas.
  """
  use SanctumWeb, :live_view

  on_mount {SanctumWeb.LiveUserAuth, :live_user_optional}

  alias Sanctum.Decks.Stats

  @hero_limit 15

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
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:stats}>
      <.header>
        Vault Stats
        <:subtitle>
          The deck vault by the numbers — growth over time, hero popularity, and aspect splits.
        </:subtitle>
      </.header>

      <div :if={@stats == nil} class="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <div :for={_ <- 1..4} class="h-20 animate-pulse border-[3px] border-neutral bg-base-300" />
      </div>

      <div :if={@stats != nil} class="flex flex-col gap-6">
        <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <.stat_tile label="Decks" value={@stats.totals.decks} />
          <.stat_tile label="Heroes built" value={@stats.totals.heroes} />
          <.stat_tile label="Added this month" value={@stats.totals.this_month} />
          <.text_tile label="Most built hero" value={top_hero_name(@stats.per_hero)} />
        </div>

        <.chart_panel
          :if={@stats.totals.decks > 0}
          id="decks-by-month"
          title="Decks added over time"
          subtitle="New decks per month, by their MarvelCDB publish date."
          option={by_month_option(@stats.by_month)}
          height="h-80"
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
          title={"Top #{length(@stats.per_hero)} heroes"}
          subtitle={"Heroes with the most decks in the vault, of #{@stats.totals.heroes} heroes built."}
          option={per_hero_option(@stats.per_hero)}
          height="h-[560px]"
        >
          <:table_head>
            <th class="pr-6 text-left">Hero</th>
            <th class="text-right">Decks</th>
          </:table_head>
          <tr :for={{name, count} <- @stats.per_hero}>
            <td class="pr-6">{name}</td>
            <td class="text-right tabular-nums">{count}</td>
          </tr>
        </.chart_panel>

        <.chart_panel
          :if={@stats.totals.decks > 0}
          id="decks-by-aspect"
          title="Decks by aspect"
          subtitle="Multi-aspect decks count once under each aspect; basic decks run no aspect."
          option={by_aspect_option(@stats.by_aspect)}
          height="h-72"
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
  slot :table_head, required: true
  slot :inner_block, required: true

  defp chart_panel(assigns) do
    ~H"""
    <.panel class="p-4 sm:p-5">
      <h2 class="font-anton text-lg uppercase tracking-[0.05em]">{@title}</h2>
      <p class="mb-3 font-barlow-condensed text-sm text-base-content/55">{@subtitle}</p>
      <div
        id={"#{@id}-chart"}
        phx-hook="Chart"
        phx-update="ignore"
        data-option={Jason.encode!(@option)}
        class={["w-full", @height]}
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

  defp stat_tile(assigns) do
    ~H"""
    <div class="border-[3px] border-neutral bg-base-300 px-4 py-3">
      <div class="font-bangers text-3xl leading-none text-primary">{@value}</div>
      <div class="mt-1 font-ibm-mono text-[11px] uppercase tracking-[0.15em] text-base-content/55">
        {@label}
      </div>
    </div>
    """
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
    socket = assign(socket, page_title: "Vault Stats", stats: nil)

    # Defer the rollup queries past the static render so the shell paints
    # immediately (same pattern as the admin health snapshot).
    socket =
      if connected?(socket), do: start_async(socket, :load_stats, &load_stats/0), else: socket

    {:ok, socket}
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
      per_hero: Stats.per_hero(@hero_limit),
      by_aspect: Stats.by_aspect()
    }
  end

  defp top_hero_name([{name, _count} | _]), do: name
  defp top_hero_name([]), do: "—"

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
      grid: %{left: 8, right: 16, top: 16, bottom: 8, containLabel: true},
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
      grid: %{left: 8, right: 40, top: 8, bottom: 8, containLabel: true},
      tooltip: %{trigger: "item"},
      xAxis: %{type: "value", minInterval: 1},
      yAxis: %{type: "category", data: Enum.map(rows, &elem(&1, 0))},
      series: [
        %{
          name: "Decks",
          type: "bar",
          data: Enum.map(rows, &elem(&1, 1)),
          barWidth: 16,
          itemStyle: %{color: @gold, borderRadius: [0, 4, 4, 0]},
          label: %{show: true, position: "right", color: @muted, fontSize: 12}
        }
      ]
    }
  end

  defp by_aspect_option(rows) do
    rows = Enum.reverse(rows)

    %{
      grid: %{left: 8, right: 40, top: 8, bottom: 8, containLabel: true},
      tooltip: %{trigger: "item"},
      xAxis: %{type: "value", minInterval: 1},
      yAxis: %{type: "category", data: Enum.map(rows, fn {key, _} -> aspect_label(key) end)},
      series: [
        %{
          name: "Decks",
          type: "bar",
          data:
            Enum.map(rows, fn {key, count} ->
              %{value: count, itemStyle: %{color: aspect_color(key)}}
            end),
          barWidth: 16,
          itemStyle: %{borderRadius: [0, 4, 4, 0]},
          label: %{show: true, position: "right", color: @muted, fontSize: 12}
        }
      ]
    }
  end
end
