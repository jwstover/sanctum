// Description-editor enhancements for the deck writeup textarea.
//
// Caret-anchored autocomplete pickers, opened by a trigger character:
//
//   `#query` — card mentions (the trigger MarvelCDB's deck editor uses).
//   Matches are searched server-side (the hosting LiveView answers the
//   hook's "card_mention" event); accepting inserts the `[Name](/card/CODE)`
//   markdown that Sanctum.Decks.Writeup already resolves.
//
//   `$query` — ChampionsIcons symbols (resources, boost, crisis, …). The
//   list rides in on the element's data-icons attribute (single source of
//   truth: Sanctum.CardText.icons/0) and filters locally; accepting inserts
//   the `[token]` code Writeup renders to a glyph.
//
// A formatting toolbar (any [data-md-cmd] button inside the hook element):
// wrap/toggle commands for bold/italic/heading/list/quote/link, plus Card
// and Icon buttons that save the caret and ask the LiveView to open the
// search-and-pick overlay ("open_picker"); the pick comes back as a
// "writeup:insert" event and is spliced in at the saved caret.
//
// All of it is editor sugar only — the stored writeup stays plain
// CommonMark plus MarvelCDB's token conventions.
//
// Expects the hooked element to wrap the <textarea> and a positioned
// [data-mention-listbox] dropdown (see the description tab in DeckLive.Build).

const MIN_CARD_QUERY = 2
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

// The nearest trigger character before the caret, with the query typed after
// it. Both trigger chars double as ordinary text (`#` starts markdown
// headings, `$` prices), so only a word-starting occurrence counts, and the
// query shape must still look like an in-progress mention: for `#`, text
// that doesn't open with a space; for `$`, token letters only (so `$5`
// never opens the picker).
function findTrigger(value, caret) {
  const start = Math.max(value.lastIndexOf("#", caret - 1), value.lastIndexOf("$", caret - 1))
  if (start === -1 || start + 1 > caret) return null

  const before = value[start - 1]
  if (before !== undefined && !/[\s(]/.test(before)) return null

  const kind = value[start] === "#" ? "card" : "icon"
  const query = value.slice(start + 1, caret)
  if (query.length > MAX_QUERY) return null

  if (kind === "card" && (query.startsWith(" ") || /[\n#${}[\]()]/.test(query))) return null
  if (kind === "icon" && !/^[a-z_]*$/i.test(query)) return null
  return {start, kind, query}
}

export default {
  mounted() {
    this.textarea = this.el.querySelector("textarea")
    this.listbox = this.el.querySelector("[data-mention-listbox]")
    this.icons = JSON.parse(this.el.dataset.icons || "[]")
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

    // Toolbar buttons, delegated. mousedown + preventDefault so the textarea
    // keeps its focus/selection while the command runs.
    this.onToolbar = (e) => {
      const btn = e.target.closest("[data-md-cmd]")
      if (!btn) return
      e.preventDefault()
      this.command(btn.dataset.mdCmd)
    }
    this.el.addEventListener("mousedown", this.onToolbar)

    // A pick from the LiveView overlay, spliced in at the caret saved when
    // the picker opened.
    this.handleEvent("writeup:insert", ({text}) => {
      const [s, e] = this.saved ?? [this.textarea.value.length, this.textarea.value.length]
      this.replaceRange(s, e, text)
      this.saved = null
    })
  },

  destroyed() {
    clearTimeout(this.timer)
  },

  // -- toolbar commands -------------------------------------------------------

  command(cmd) {
    const t = this.textarea

    switch (cmd) {
      case "bold":
        return this.wrapSelection("**", "**", "bold text")
      case "italic":
        return this.wrapSelection("*", "*", "italic text")
      case "heading":
        return this.toggleLinePrefix("## ")
      case "ul":
        return this.toggleLinePrefix("- ")
      case "quote":
        return this.toggleLinePrefix("> ")
      case "link":
        return this.insertLink()
      case "card":
      case "icon":
        this.saved = [t.selectionStart ?? t.value.length, t.selectionEnd ?? t.value.length]
        return this.pushEvent("open_picker", {kind: cmd})
    }
  },

  // Replace [start, end) with text, going through execCommand when possible
  // so the browser's native undo stack survives (deprecated but universally
  // shipped; setRangeText is the no-undo fallback).
  replaceRange(start, end, text) {
    const t = this.textarea
    t.focus()
    if (start === end && text === "") return
    t.setSelectionRange(start, end)

    let ok = false
    try {
      ok = text === ""
        ? document.execCommand("delete")
        : document.execCommand("insertText", false, text)
    } catch {
      ok = false
    }

    if (!ok) {
      t.setRangeText(text, start, end, "end")
      t.dispatchEvent(new Event("input", {bubbles: true}))
    }
  },

  // Wrap the selection in prefix/suffix, or unwrap when it's already wrapped.
  // With nothing selected, insert the placeholder pre-selected so typing
  // replaces it.
  wrapSelection(prefix, suffix, placeholder) {
    const t = this.textarea
    const [s, e] = [t.selectionStart, t.selectionEnd]
    const sel = t.value.slice(s, e)

    if (
      s >= prefix.length &&
      t.value.slice(s - prefix.length, s) === prefix &&
      t.value.slice(e, e + suffix.length) === suffix
    ) {
      this.replaceRange(s - prefix.length, e + suffix.length, sel)
      t.setSelectionRange(s - prefix.length, s - prefix.length + sel.length)
      return
    }

    const inner = sel || placeholder
    this.replaceRange(s, e, prefix + inner + suffix)
    t.setSelectionRange(s + prefix.length, s + prefix.length + inner.length)
  },

  // Add prefix to every line the selection touches, or strip it when every
  // non-blank line already carries it.
  toggleLinePrefix(prefix) {
    const t = this.textarea
    const [s, e] = [t.selectionStart, t.selectionEnd]
    const lineStart = t.value.lastIndexOf("\n", s - 1) + 1
    let lineEnd = t.value.indexOf("\n", e)
    if (lineEnd === -1) lineEnd = t.value.length

    const block = t.value.slice(lineStart, lineEnd)
    const lines = block.split("\n")

    let next
    if (block.trim() === "" && lines.length === 1) {
      next = prefix
    } else {
      const allPrefixed = lines.every((l) => l.startsWith(prefix) || l.trim() === "")
      next = lines
        .map((l) => {
          if (l.trim() === "") return l
          return allPrefixed ? l.slice(prefix.length) : prefix + l
        })
        .join("\n")
    }

    this.replaceRange(lineStart, lineEnd, next)
    const pos = lineStart + next.length
    t.setSelectionRange(pos, pos)
  },

  // Wrap the selection as a markdown link and pre-select the url placeholder.
  insertLink() {
    const t = this.textarea
    const [s, e] = [t.selectionStart, t.selectionEnd]
    const sel = t.value.slice(s, e) || "link text"
    this.replaceRange(s, e, `[${sel}](url)`)
    const urlStart = s + sel.length + 3
    t.setSelectionRange(urlStart, urlStart + 3)
  },

  // -- trigger pickers --------------------------------------------------------

  detect() {
    const trigger = findTrigger(this.textarea.value, this.textarea.selectionStart ?? 0)
    this.trigger = trigger
    clearTimeout(this.timer)

    if (!trigger) return this.close()

    // Icons filter locally — no debounce, no round-trip.
    if (trigger.kind === "icon") {
      const q = trigger.query.toLowerCase()
      return this.show(
        this.icons.filter((i) => i.token.includes(q) || i.label.toLowerCase().includes(q))
      )
    }

    if (trigger.query.length < MIN_CARD_QUERY) return this.close()

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
      row.appendChild(item.glyph ? this.iconVisual(item) : this.cardVisual(item))
      row.appendChild(this.textCol(item))

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

  cardVisual(item) {
    const thumb = document.createElement(item.image_url ? "img" : "div")
    thumb.className = "mention-thumb"
    if (item.image_url) {
      thumb.src = item.image_url
      thumb.loading = "lazy"
      thumb.alt = ""
    }
    return thumb
  },

  iconVisual(item) {
    const glyph = document.createElement("span")
    glyph.className = `mention-glyph font-champions ${item.color || ""}`
    glyph.textContent = item.glyph
    return glyph
  },

  textCol(item) {
    const text = document.createElement("div")
    text.className = "mention-text"
    const name = document.createElement("div")
    name.className = "qi-option-label"
    name.textContent = item.name || item.label
    text.appendChild(name)

    const detail = item.glyph
      ? `[${item.token}]`
      : [item.subname, item.type].filter(Boolean).join(" · ")

    if (detail) {
      const detailEl = document.createElement("div")
      detailEl.className = "qi-option-detail"
      detailEl.textContent = detail
      text.appendChild(detailEl)
    }
    return text
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

    const end = this.textarea.selectionStart ?? trigger.start
    const insert = item.glyph ? `[${item.token}]` : `[${item.name}](/card/${item.code})`
    // replaceRange fires input (natively or manually), so the form's
    // phx-change keeps the LiveView's draft assign in sync.
    this.replaceRange(trigger.start, end, insert)
    this.close()
  },

  handleKey(e) {
    if ((e.metaKey || e.ctrlKey) && !e.shiftKey && !e.altKey) {
      const cmd = {b: "bold", i: "italic", k: "link"}[e.key.toLowerCase()]
      if (cmd) {
        e.preventDefault()
        return this.command(cmd)
      }
    }

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
