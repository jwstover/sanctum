// ECharts LiveView hook. The server renders a full chart option as JSON in
// data-option; this hook initializes the canvas, registers the comic-dossier
// chart chrome as a theme, and re-applies the option whenever the attribute
// changes. The element carries phx-update="ignore" so LiveView never patches
// the DOM ECharts owns — attribute updates still fire updated().
import * as echarts from "echarts/core"
import {BarChart, LineChart} from "echarts/charts"
import {GridComponent, TooltipComponent} from "echarts/components"
import {CanvasRenderer} from "echarts/renderers"

echarts.use([BarChart, LineChart, GridComponent, TooltipComponent, CanvasRenderer])

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
    this.resizeObserver = new ResizeObserver(() => this.chart.resize())
    this.resizeObserver.observe(this.el)
  },

  updated() {
    this.apply()
  },

  destroyed() {
    this.resizeObserver?.disconnect()
    this.chart?.dispose()
  },

  apply() {
    const option = JSON.parse(this.el.dataset.option || "{}")
    this.chart.setOption(option, {notMerge: true})
  },
}

export default Chart
