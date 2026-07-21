// Site-wide search overlay: the QueryInput pattern (syntax-highlight mirror +
// server-driven suggestions) inside a command-palette dialog — centered modal
// on desktop, slide-up sheet on mobile.
//
// Opening/closing is fully client-side: trigger buttons dispatch a
// `sanctum:open-search` window event (see Layouts.open_search/1), Cmd/Ctrl+K
// toggles, Escape and the backdrop close. The hook re-asserts visibility in
// updated() because LiveView patches reset the server-rendered `hidden`
// classes.
//
// Inside the panel, two result sections share one virtual keyboard list:
//
//   * a JS-managed suggestion listbox (phx-update="ignore", filled from the
//     "suggest" reply — text-insert items, exactly like QueryInput)
//   * server-rendered result rows/links marked with [data-gs-nav], patched by
//     LiveView as the debounced "search" form event returns groups
//
// Indexes below items.length are suggestions (Enter splices the insert
// text); the rest are result anchors (Enter clicks them). Enter with nothing
// active opens the first result. The hook lives inside a LiveComponent, so
// all events go through pushEventTo(this.el, ...).

import {paintMirror} from "./query-syntax"

export default {
  mounted() {
    this.input = this.el.querySelector("input")
    this.mirror = document.getElementById(`${this.el.id}-mirror`)
    this.listbox = document.getElementById(`${this.el.id}-listbox`)
    this.panel = document.getElementById(`${this.el.id}-panel`)
    this.overlay = this.el.closest("[data-gs-overlay]")
    this.knownFields = new Set(JSON.parse(this.el.dataset.fields || "[]"))
    this.items = []
    this.navEls = []
    this.active = -1
    this.open = false
    this.overlayOpen = false
    this.suggestTimer = null

    this.paint()
    this.scanResults()

    this.onInput = () => { this.paint(); this.queueSuggest(); this.show() }
    this.onScroll = () => { this.mirror.scrollLeft = this.input.scrollLeft }
    this.onFocus = () => this.queueSuggest()
    this.onClick = () => this.queueSuggest()
    this.onKeydown = (e) => this.handleKey(e)

    this.input.addEventListener("input", this.onInput)
    this.input.addEventListener("scroll", this.onScroll)
    this.input.addEventListener("focus", this.onFocus)
    this.input.addEventListener("click", this.onClick)
    this.input.addEventListener("keydown", this.onKeydown)

    this.onBackdrop = () => this.closeOverlay()
    this.overlay
      ?.querySelector("[data-gs-close]")
      ?.addEventListener("click", this.onBackdrop)

    this.onOpenEvent = () => this.openOverlay()
    window.addEventListener("sanctum:open-search", this.onOpenEvent)

    this.onGlobalKey = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault()
        this.overlayOpen ? this.closeOverlay() : this.openOverlay()
      }
    }
    window.addEventListener("keydown", this.onGlobalKey)
  },

  // LiveView patched the component (new result groups, cleared input, …):
  // repaint, rescan the result anchors, and re-assert overlay/panel
  // visibility (the patch resets the server-rendered "hidden" classes).
  updated() {
    this.paint()
    this.scanResults()
    this.syncOverlay()
    this.syncPanel()
  },

  destroyed() {
    clearTimeout(this.suggestTimer)
    window.removeEventListener("sanctum:open-search", this.onOpenEvent)
    window.removeEventListener("keydown", this.onGlobalKey)
    document.body.classList.remove("overflow-hidden")
  },

  paint() {
    paintMirror(this.mirror, this.input.value, this.knownFields)
    this.mirror.scrollLeft = this.input.scrollLeft
  },

  // -- overlay -------------------------------------------------------------------

  openOverlay() {
    this.overlayOpen = true
    this.open = true
    this.syncOverlay()
    this.syncPanel()
    this.animateSheetIn()
    this.input.focus()
    this.input.select()
    this.queueSuggest()
  },

  // The slide-up runs off a temporary class so it plays exactly once per
  // open — an always-on animation would replay every time a LiveView patch
  // re-toggles the overlay's `hidden` class (a display flip resets CSS
  // animations).
  animateSheetIn() {
    const sheet = this.overlay?.querySelector(".gs-sheet")
    if (!sheet) return
    sheet.classList.add("gs-sheet-opening")
    sheet.addEventListener(
      "animationend",
      () => sheet.classList.remove("gs-sheet-opening"),
      {once: true}
    )
  },

  closeOverlay() {
    this.overlayOpen = false
    this.open = false
    this.setActive(-1)
    this.items = []
    this.listbox.textContent = ""
    this.syncOverlay()
    this.syncPanel()
    this.input.blur()
  },

  syncOverlay() {
    if (!this.overlay) return
    this.overlay.classList.toggle("hidden", !this.overlayOpen)
    if (this.overlayOpen && !this.scrollLocked) this.lockScroll()
    if (!this.overlayOpen && this.scrollLocked) this.unlockScroll(true)
  },

  // `overflow: hidden` on <body> doesn't stop touch scrolling on iOS — the
  // page behind the sheet keeps panning. Pinning the body with position:fixed
  // (offset to the current scroll) is the reliable lock; the offset is
  // restored on close.
  lockScroll() {
    this.scrollLocked = true
    this.savedScrollY = window.scrollY
    const style = document.body.style
    style.position = "fixed"
    style.top = `-${this.savedScrollY}px`
    style.left = "0"
    style.right = "0"
    style.width = "100%"
  },

  // `restore` scrolls back to the pre-lock position — wanted when the user
  // closes the overlay in place, not when the hook dies mid-navigation (the
  // next page starts fresh).
  unlockScroll(restore) {
    this.scrollLocked = false
    const style = document.body.style
    style.position = ""
    style.top = ""
    style.left = ""
    style.right = ""
    style.width = ""
    if (restore) window.scrollTo(0, this.savedScrollY ?? 0)
  },

  // -- results section ---------------------------------------------------------

  // Collect the server-rendered result anchors. Read-only: their ids come
  // from the server (mutating ids on LiveView-managed elements corrupts DOM
  // patching), and listeners bind once per element.
  scanResults() {
    this.navEls = Array.from(this.el.querySelectorAll("[data-gs-nav]"))
    this.navEls.forEach((el) => {
      el.classList.remove("gs-active")
      if (!el.__gsBound) {
        el.__gsBound = true
        el.addEventListener("mousemove", () => {
          const i = this.navEls.indexOf(el)
          if (i >= 0) this.setActive(this.items.length + i)
        })
      }
    })
    // Result rows changed under the cursor — a result index no longer points
    // where it did. Suggestion indexes are still valid.
    if (this.active >= this.items.length) this.setActive(-1)
  },

  // -- suggestions section -------------------------------------------------------

  queueSuggest() {
    clearTimeout(this.suggestTimer)
    this.suggestTimer = setTimeout(() => {
      this.pushEventTo(this.el, "suggest",
        {value: this.input.value, cursor: this.input.selectionStart ?? 0},
        (reply) => this.showSuggestions(reply)
      )
    }, 120)
  },

  showSuggestions(reply) {
    if (!this.overlayOpen || document.activeElement !== this.input) return
    this.items = reply.items || []
    this.replaceStart = reply.start
    this.replaceLength = reply.length
    this.setActive(-1)

    this.listbox.textContent = ""
    this.listbox.classList.toggle("hidden", this.items.length === 0)

    this.items.forEach((item, i) => {
      const li = document.createElement("div")
      li.id = `${this.el.id}-opt-${i}`
      li.setAttribute("role", "option")
      li.className = "qi-option"
      li.dataset.index = i

      const label = document.createElement("span")
      label.className = `qi-option-label qi-kind-${item.kind}`
      label.textContent = item.label
      li.appendChild(label)

      if (item.detail) {
        const detail = document.createElement("span")
        detail.className = "qi-option-detail"
        detail.textContent = item.detail
        li.appendChild(detail)
      }

      // mousedown (not click) so the input never loses focus.
      li.addEventListener("mousedown", (e) => {
        e.preventDefault()
        this.accept(i)
      })
      li.addEventListener("mousemove", () => this.setActive(i))

      this.listbox.appendChild(li)
    })

    this.show()
  },

  accept(i) {
    const item = this.items[i]
    if (!item) return

    const v = this.input.value
    const before = v.slice(0, this.replaceStart)
    const after = v.slice(this.replaceStart + this.replaceLength)
    this.input.value = before + item.insert + after

    const caret = this.replaceStart + item.insert.length
    this.input.setSelectionRange(caret, caret)
    this.paint()
    this.items = []
    this.listbox.textContent = ""
    this.listbox.classList.add("hidden")
    this.setActive(-1)

    // Bubble a real input event so the form's phx-change fires (debounced
    // results refresh), then offer the next completion step.
    this.input.dispatchEvent(new Event("input", {bubbles: true}))
  },

  // -- panel + virtual list -------------------------------------------------------

  show() {
    this.open = true
    this.syncPanel()
  },

  syncPanel() {
    if (!this.panel) return
    const empty = this.items.length === 0 && this.panel.querySelector("[data-gs-content]") == null
    this.panel.classList.toggle("hidden", !this.open || empty)
    this.listbox.classList.toggle("hidden", this.items.length === 0)
    this.input.setAttribute("aria-expanded", this.open ? "true" : "false")
  },

  total() {
    return this.items.length + this.navEls.length
  },

  setActive(i) {
    this.active = i

    for (const li of this.listbox.children) {
      li.classList.toggle("qi-active", Number(li.dataset.index) === i)
    }
    this.navEls.forEach((el, j) => {
      el.classList.toggle("gs-active", this.items.length + j === i)
    })

    if (i >= 0 && i < this.items.length) {
      this.input.setAttribute("aria-activedescendant", `${this.el.id}-opt-${i}`)
      this.listbox.children[i]?.scrollIntoView({block: "nearest"})
    } else if (i >= this.items.length && i < this.total()) {
      const el = this.navEls[i - this.items.length]
      this.input.setAttribute("aria-activedescendant", el.id)
      el.scrollIntoView({block: "nearest"})
    } else {
      this.input.removeAttribute("aria-activedescendant")
    }
  },

  handleKey(e) {
    switch (e.key) {
      case "ArrowDown":
        e.preventDefault()
        if (this.total() > 0) this.setActive((this.active + 1) % this.total())
        break
      case "ArrowUp":
        e.preventDefault()
        if (this.total() > 0) this.setActive((this.active - 1 + this.total()) % this.total())
        break
      case "Enter":
        if (this.active >= 0 && this.active < this.items.length) {
          e.preventDefault()
          this.accept(this.active)
        } else if (this.active >= this.items.length && this.navEls[this.active - this.items.length]) {
          e.preventDefault()
          this.navEls[this.active - this.items.length].click()
        } else if (this.navEls.length > 0) {
          // nothing highlighted: open the first result
          e.preventDefault()
          this.navEls[0].click()
        }
        // otherwise fall through to the form's phx-submit
        break
      case "Tab":
        if (this.active >= 0 && this.active < this.items.length) {
          e.preventDefault()
          this.accept(this.active)
        } else if (this.items.length > 0) {
          e.preventDefault()
          this.accept(0)
        }
        break
      case "Escape":
        e.preventDefault()
        if (this.active >= 0) {
          this.setActive(-1)
        } else {
          this.closeOverlay()
        }
        break
    }
  },
}
