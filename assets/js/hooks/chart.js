// ECharts LiveView hook. The server renders a full chart option as JSON in
// data-option; this hook initializes the canvas, registers the comic-dossier
// chart chrome as a theme, and re-applies the option whenever the attribute
// changes. The element carries phx-update="ignore" so LiveView never patches
// the DOM ECharts owns — attribute updates still fire updated().
import * as echarts from "echarts/core"
import {BarChart, LineChart, PieChart} from "echarts/charts"
import {GridComponent, MarkLineComponent, MarkPointComponent, TooltipComponent} from "echarts/components"
import {CanvasRenderer} from "echarts/renderers"
import {UniversalTransition} from "echarts/features"

echarts.use([
  BarChart,
  LineChart,
  PieChart,
  GridComponent,
  MarkLineComponent,
  MarkPointComponent,
  TooltipComponent,
  CanvasRenderer,
  UniversalTransition,
])

const INK = "#f4f1ea"
const MUTED = "rgba(244, 241, 234, 0.55)"
const HAIRLINE = "#2a2a30"
const CONDENSED = "'Barlow Condensed', sans-serif"

// Recessive hairline axes/grid, muted ink labels, dossier-panel tooltip.
// Data, series colors, and per-chart geometry come from the server.
const axis = {
  axisLine: {lineStyle: {color: HAIRLINE}},
  axisTick: {show: false},
  axisLabel: {color: MUTED, fontFamily: CONDENSED, fontSize: 12},
  splitLine: {show: false},
}

echarts.registerTheme("sanctum", {
  textStyle: {fontFamily: CONDENSED, color: INK},
  categoryAxis: axis,
  timeAxis: axis,
  valueAxis: {
    ...axis,
    axisLine: {show: false},
    splitLine: {show: true, lineStyle: {color: HAIRLINE, width: 1, type: "solid"}},
  },
  tooltip: {
    backgroundColor: "#1a1a1f",
    borderColor: "#08080a",
    borderWidth: 2,
    padding: [8, 12],
    textStyle: {color: INK, fontFamily: CONDENSED},
    extraCssText: "border-radius: 0; box-shadow: 4px 4px 0 rgba(0, 0, 0, 0.55);",
  },
})

const Chart = {
  mounted() {
    this.chart = echarts.init(this.el, "sanctum", {renderer: "canvas"})
    this.apply()
    // apply() already resizes for server-driven height changes; only react to
    // sizes the chart doesn't know yet (viewport changes), so we never
    // re-layout mid-transition.
    this.resizeObserver = new ResizeObserver(() => {
      if (
        this.el.clientWidth !== this.chart.getWidth() ||
        this.el.clientHeight !== this.chart.getHeight()
      ) {
        this.chart.resize()
      }
    })
    this.resizeObserver.observe(this.el)

    // Drill-down: when the server tags the element with data-click-event,
    // clicking a mark whose data item carries a `drill` payload pushes that
    // event with the payload. The attribute is read per click, so the server
    // can swap or disable it (e.g. per drill level) without re-mounting.
    this.chart.on("click", (params) => {
      const event = this.el.dataset.clickEvent
      if (event && params.data && params.data.drill) {
        this.pushEvent(event, {...params.data.drill, name: params.name})
      }
    })
  },

  updated() {
    this.apply()
  },

  destroyed() {
    this.resizeObserver?.disconnect()
    this.chart?.dispose()
  },

  apply() {
    // phx-update="ignore" only lets data-* attributes through on updates, so
    // the server sends height as data-height and we apply it here. Resize
    // BEFORE setOption: resizing mid-transition corrupts the morph layout.
    if (this.el.dataset.height) {
      this.el.style.height = this.el.dataset.height
      this.chart.resize()
    }
    const option = JSON.parse(this.el.dataset.option || "{}")
    this.chart.setOption(option, {notMerge: true})
  },
}

export default Chart
