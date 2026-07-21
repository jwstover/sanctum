// Drag-to-dismiss for slide-up panes (the deckbuilder's deck panel, the
// filter sheet). The [data-drag-handle] element owns both gestures: a short
// press is a tap (close), a downward drag past the threshold dismisses,
// anything else springs back. The dismiss pushes the event named by the
// pane's data-dismiss-event attribute (default "toggle_panel").
const THRESHOLD = 110
const TAP_SLOP = 8

export default {
  mounted() {
    const pane = this.el
    const handle = pane.querySelector("[data-drag-handle]")
    let startY = null
    let dy = 0

    handle.addEventListener("pointerdown", (e) => {
      startY = e.clientY
      dy = 0
      handle.setPointerCapture(e.pointerId)
    })

    handle.addEventListener("pointermove", (e) => {
      if (startY == null) return
      dy = Math.max(0, e.clientY - startY)
      pane.style.transition = "none"
      pane.style.transform = `translateY(${dy}px)`
    })

    const finish = () => {
      if (startY == null) return
      pane.style.transition = ""
      if (dy < TAP_SLOP || dy > THRESHOLD) {
        // Slide the rest of the way down NOW — translateY(100%) matches the
        // closed-state class, so when the server patch swaps classes and
        // `updated()` drops the inline style, nothing visibly moves. Clearing
        // the transform here instead would animate the pane back open while
        // the round-trip is in flight.
        pane.style.transform = "translateY(100%)"
        this.pushEvent(pane.dataset.dismissEvent || "toggle_panel", {})
      } else {
        pane.style.transform = ""
      }
      startY = null
      dy = 0
    }

    handle.addEventListener("pointerup", finish)
    handle.addEventListener("pointercancel", finish)
  },

  // A server patch (open/close) must never fight a leftover drag frame.
  updated() {
    this.el.style.transform = ""
    this.el.style.transition = ""
  },
}
