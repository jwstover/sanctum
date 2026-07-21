// Card-mention autocomplete for the deck description textarea.
//
// Typing `#` opens a card picker anchored at the caret (the same trigger
// MarvelCDB's deck editor uses); the text after it is searched server-side
// (the hosting LiveView answers the hook's "card_mention" event with catalog
// matches). Accepting a card replaces `#query` with a plain markdown link
// `[Name](/card/CODE)` — the trigger is editor sugar only; the stored
// writeup stays the CommonMark that Sanctum.Decks.Writeup already resolves.
//
// Expects the hooked element to wrap the <textarea> and a positioned
// [data-mention-listbox] dropdown (see the description tab in DeckLive.Build).

const MIN_QUERY = 2
const MAX_QUERY = 50

// Copied onto the offscreen mirror so its text wraps exactly like the
// textarea and the caret marker lands at the true pixel offset.
const MIRROR_PROPS = [
  "boxSizing", "width", "paddingTop", "paddingRight", "paddingBottom", "paddingLeft",
  "borderTopWidth", "borderRightWidth", "borderBottomWidth", "borderLeftWidth",
  "fontFamily", "fontSize", "fontWeight", "fontStyle", "letterSpacing",
  "lineHeight", "textTransform", "wordSpacing", "tabSize",
]

// Pixel offset of `index` within the textarea's content box, via a hidden
// mirror div (the standard textarea-caret-position technique).
function caretOffset(textarea, index) {
  const style = getComputedStyle(textarea)
  const div = document.createElement("div")
  for (const prop of MIRROR_PROPS) div.style[prop] = style[prop]
  div.style.position = "absolute"
  div.style.top = "0"
  div.style.left = "-9999px"
  div.style.visibility = "hidden"
  div.style.whiteSpace = "pre-wrap"
  div.style.overflowWrap = "break-word"
  div.textContent = textarea.value.slice(0, index)

  const marker = document.createElement("span")
  marker.textContent = "​"
  div.appendChild(marker)
  document.body.appendChild(div)

  const offset = {
    top: marker.offsetTop - textarea.scrollTop,
    left: marker.offsetLeft - textarea.scrollLeft,
    height: marker.offsetHeight || parseFloat(style.lineHeight) || 20,
  }
  div.remove()
  return offset
}

// The nearest `#` before the caret, with the query typed after it. `#` is
// also markdown heading syntax, so only a word-starting `#` immediately
// followed by text counts: `##` and `# Heading` never trigger, and neither
// does anything that no longer looks like an in-progress mention.
function findTrigger(value, caret) {
  const start = value.lastIndexOf("#", caret - 1)
  if (start === -1 || start + 1 > caret) return null

  const before = value[start - 1]
  if (before !== undefined && !/[\s(]/.test(before)) return null

  const query = value.slice(start + 1, caret)
  if (query.startsWith(" ") || query.length > MAX_QUERY || /[\n#{}[\]()]/.test(query)) return null
  return {start, query}
}

export default {
  mounted() {
    this.textarea = this.el.querySelector("textarea")
    this.listbox = this.el.querySelector("[data-mention-listbox]")
    this.items = []
    this.active = 0
    this.trigger = null
    this.timer = null

    this.onInput = () => this.detect()
    this.onKeydown = (e) => this.handleKey(e)
    // Arrow/Home/End moves don't fire `input`; re-check whether the caret is
    // still inside the trigger region.
    this.onKeyup = (e) => {
      if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home", "End"].includes(e.key)) {
        if (!this.isOpen() || e.key === "ArrowLeft" || e.key === "ArrowRight") this.detect()
      }
    }
    this.onClick = () => this.detect()
    this.onBlur = () => setTimeout(() => this.close(), 120)
    this.onScroll = () => this.isOpen() && this.position()

    this.textarea.addEventListener("input", this.onInput)
    this.textarea.addEventListener("keydown", this.onKeydown)
    this.textarea.addEventListener("keyup", this.onKeyup)
    this.textarea.addEventListener("click", this.onClick)
    this.textarea.addEventListener("blur", this.onBlur)
    this.textarea.addEventListener("scroll", this.onScroll)
  },

  destroyed() {
    clearTimeout(this.timer)
  },

  detect() {
    const trigger = findTrigger(this.textarea.value, this.textarea.selectionStart ?? 0)
    this.trigger = trigger
    clearTimeout(this.timer)

    if (!trigger || trigger.query.length < MIN_QUERY) return this.close()

    this.timer = setTimeout(() => {
      this.pushEvent("card_mention", {q: trigger.query}, (reply) => {
        // Stale reply: the trigger moved or closed while the request flew.
        if (this.trigger?.start !== trigger.start || this.trigger?.query !== trigger.query) return
        this.show(reply.items || [])
      })
    }, 150)
  },

  show(items) {
    if (document.activeElement !== this.textarea) return
    this.items = items
    if (items.length === 0) return this.close()

    this.listbox.textContent = ""
    items.forEach((item, i) => {
      const row = document.createElement("div")
      row.setAttribute("role", "option")
      row.id = `${this.el.id}-opt-${i}`
      row.className = "qi-option mention-option"
      row.dataset.index = i

      const thumb = document.createElement(item.image_url ? "img" : "div")
      thumb.className = "mention-thumb"
      if (item.image_url) {
        thumb.src = item.image_url
        thumb.loading = "lazy"
        thumb.alt = ""
      }
      row.appendChild(thumb)

      const text = document.createElement("div")
      text.className = "mention-text"
      const name = document.createElement("div")
      name.className = "qi-option-label"
      name.textContent = item.name
      text.appendChild(name)

      const detail = [item.subname, item.type].filter(Boolean).join(" · ")
      if (detail) {
        const detailEl = document.createElement("div")
        detailEl.className = "qi-option-detail"
        detailEl.textContent = detail
        text.appendChild(detailEl)
      }
      row.appendChild(text)

      // mousedown (not click) so the textarea never loses focus.
      row.addEventListener("mousedown", (e) => {
        e.preventDefault()
        this.accept(i)
      })
      row.addEventListener("mousemove", () => this.setActive(i))
      this.listbox.appendChild(row)
    })

    this.listbox.classList.remove("hidden")
    this.position()
    this.setActive(0)
  },

  position() {
    if (!this.trigger) return
    const {top, left, height} = caretOffset(this.textarea, this.trigger.start)
    const maxLeft = this.el.clientWidth - this.listbox.offsetWidth
    this.listbox.style.top = `${this.textarea.offsetTop + top + height + 4}px`
    this.listbox.style.left =
      `${Math.min(Math.max(0, this.textarea.offsetLeft + left), Math.max(0, maxLeft))}px`
  },

  close() {
    this.listbox.classList.add("hidden")
    this.listbox.textContent = ""
    this.items = []
    this.active = 0
  },

  isOpen() {
    return !this.listbox.classList.contains("hidden") && this.items.length > 0
  },

  setActive(i) {
    this.active = i
    for (const row of this.listbox.children) {
      row.classList.toggle("qi-active", Number(row.dataset.index) === i)
    }
    this.listbox.children[i]?.scrollIntoView({block: "nearest"})
  },

  accept(i) {
    const item = this.items[i]
    const trigger = this.trigger
    if (!item || !trigger) return

    const t = this.textarea
    const end = t.selectionStart ?? trigger.start
    const insert = `[${item.name}](/card/${item.code})`
    t.value = t.value.slice(0, trigger.start) + insert + t.value.slice(end)

    const caret = trigger.start + insert.length
    t.setSelectionRange(caret, caret)
    this.close()

    // Bubble a real input event so the surrounding form's phx-change fires
    // and the LiveView's draft assign catches up.
    t.dispatchEvent(new Event("input", {bubbles: true}))
  },

  handleKey(e) {
    if (!this.isOpen()) return

    switch (e.key) {
      case "ArrowDown":
        e.preventDefault()
        this.setActive((this.active + 1) % this.items.length)
        break
      case "ArrowUp":
        e.preventDefault()
        this.setActive((this.active - 1 + this.items.length) % this.items.length)
        break
      case "Enter":
      case "Tab":
        e.preventDefault()
        this.accept(this.active)
        break
      case "Escape":
        e.preventDefault()
        e.stopPropagation()
        this.close()
        break
    }
  },
}
