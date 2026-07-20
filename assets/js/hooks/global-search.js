// Site-wide search bar: the QueryInput pattern (syntax-highlight mirror +
// server-driven suggestions) extended with a server-rendered results panel.
//
// The dropdown panel stacks two sections:
//
//   * a JS-managed suggestion listbox (phx-update="ignore", filled from the
//     "suggest" reply — text-insert items, exactly like QueryInput)
//   * server-rendered result rows/links marked with [data-gs-nav], patched by
//     LiveView as the debounced "search" form event returns groups
//
// Keyboard nav walks one virtual list across both sections: indexes below
// items.length are suggestions (Enter splices the insert text), the rest are
// result anchors (Enter clicks them). Enter with nothing active opens the
// first result. The hook lives inside a LiveComponent, so all events go
// through pushEventTo(this.el, ...).
//
// Also owns the app's global search shortcut: Cmd/Ctrl+K focuses the input.

import {paintMirror} from "./query-syntax"

export default {
  mounted() {
    this.input = this.el.querySelector("input")
    this.mirror = document.getElementById(`${this.el.id}-mirror`)
    this.listbox = document.getElementById(`${this.el.id}-listbox`)
    this.panel = document.getElementById(`${this.el.id}-panel`)
    this.knownFields = new Set(JSON.parse(this.el.dataset.fields || "[]"))
    this.items = []
    this.navEls = []
    this.active = -1
    this.open = false
    this.suggestTimer = null

    this.paint()
    this.scanResults()

    this.onInput = () => { this.paint(); this.queueSuggest(); this.show() }
    this.onScroll = () => { this.mirror.scrollLeft = this.input.scrollLeft }
    this.onFocus = () => { this.queueSuggest(); this.show() }
    this.onClick = () => this.queueSuggest()
    this.onBlur = () => setTimeout(() => this.hide(), 120)
    this.onKeydown = (e) => this.handleKey(e)

    this.input.addEventListener("input", this.onInput)
    this.input.addEventListener("scroll", this.onScroll)
    this.input.addEventListener("focus", this.onFocus)
    this.input.addEventListener("click", this.onClick)
    this.input.addEventListener("blur", this.onBlur)
    this.input.addEventListener("keydown", this.onKeydown)

    this.onGlobalKey = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault()
        this.input.focus()
        this.input.select()
      }
    }
    window.addEventListener("keydown", this.onGlobalKey)
  },

  // LiveView patched the component (new result groups, cleared input, …):
  // repaint, rescan the result anchors, and re-assert panel visibility (the
  // patch resets the server-rendered "hidden" class).
  updated() {
    this.paint()
    this.scanResults()
    this.syncPanel()
  },

  destroyed() {
    clearTimeout(this.suggestTimer)
    window.removeEventListener("keydown", this.onGlobalKey)
  },

  paint() {
    paintMirror(this.mirror, this.input.value, this.knownFields)
    this.mirror.scrollLeft = this.input.scrollLeft
  },

  // -- results section ---------------------------------------------------------

  scanResults() {
    this.navEls = Array.from(this.el.querySelectorAll("[data-gs-nav]"))
    this.navEls.forEach((el, i) => {
      el.id = `${this.el.id}-res-${i}`
      el.classList.remove("gs-active")
      el.addEventListener("mousemove", () => this.setActive(this.items.length + i))
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
    if (document.activeElement !== this.input) return
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

  hide() {
    this.open = false
    this.setActive(-1)
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
    const isOpen = this.open && !this.panel.classList.contains("hidden")

    if (!isOpen) {
      if (e.key === "ArrowDown") {
        this.queueSuggest()
        this.show()
      }
      return
    }

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
          this.hide()
          this.input.blur()
        }
        break
    }
  },
}
