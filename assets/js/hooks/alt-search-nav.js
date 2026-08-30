// Keyboard navigation for the homebrew alt-art assignment search. The hook
// wraps the official-card search input and its server-rendered result buttons
// (marked [data-alt-result], each carrying phx-click="pick_alt_target").
//
//   * mounted(): focus the input, so choosing "Assign" lands the cursor in the
//     search box with no extra click.
//   * ArrowDown/ArrowUp move a highlight across the results; Enter clicks the
//     highlighted one (which fires its phx-click).
//
// Results are re-rendered as the user types (LiveView patches the descendants),
// so updated() rescans and re-paints the highlight, clamping the active index.

const ACTIVE = "bg-base-300"

export default {
  mounted() {
    this.input = this.el.querySelector("input[name=q]")
    this.active = -1
    this.scan()
    this.input?.focus()
    this.onKeydown = (e) => this.handleKey(e)
    this.input?.addEventListener("keydown", this.onKeydown)
  },

  updated() {
    this.scan()
    if (this.active >= this.results.length) this.active = this.results.length - 1
    this.paint()
  },

  destroyed() {
    this.input?.removeEventListener("keydown", this.onKeydown)
  },

  scan() {
    this.results = Array.from(this.el.querySelectorAll("[data-alt-result]"))
    this.paint()
  },

  paint() {
    this.results.forEach((el, i) => el.classList.toggle(ACTIVE, i === this.active))
    this.results[this.active]?.scrollIntoView({block: "nearest"})
  },

  handleKey(e) {
    if (this.results.length === 0) return

    switch (e.key) {
      case "ArrowDown":
        e.preventDefault()
        this.active = (this.active + 1) % this.results.length
        this.paint()
        break
      case "ArrowUp":
        e.preventDefault()
        this.active = (this.active - 1 + this.results.length) % this.results.length
        this.paint()
        break
      case "Enter":
        if (this.active >= 0) {
          e.preventDefault()
          this.results[this.active].click()
        }
        break
    }
  },
}
