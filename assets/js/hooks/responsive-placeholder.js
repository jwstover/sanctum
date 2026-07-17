// Swaps an input's placeholder below Tailwind's `sm` breakpoint (640px):
// the server-rendered `placeholder` attribute holds the full desktop hint,
// `data-placeholder-short` the mobile variant that fits a narrow input.
const mq = window.matchMedia("(min-width: 640px)")

const ResponsivePlaceholder = {
  mounted() {
    this.full = this.el.getAttribute("placeholder") || ""
    this.apply = () => {
      const short = this.el.dataset.placeholderShort
      this.el.setAttribute("placeholder", !mq.matches && short ? short : this.full)
    }
    mq.addEventListener("change", this.apply)
    this.apply()
  },

  updated() {
    // LiveView patches restore the server-rendered (full) placeholder.
    this.apply()
  },

  destroyed() {
    mq.removeEventListener("change", this.apply)
  },
}

export default ResponsivePlaceholder
