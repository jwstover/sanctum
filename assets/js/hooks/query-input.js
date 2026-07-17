// Advanced-search query input: syntax highlighting + autocomplete.
//
// Follows GitHub's QueryBuilder pattern (their engineering blog documents why
// contenteditable was rejected as inaccessible): the real <input> renders its
// text transparent (caret/selection still visible) and an aria-hidden mirror
// <div> behind it repeats the text as colored spans. A W3C-combobox-style
// listbox offers suggestions computed *server-side* (`Sanctum.Search.Suggest`)
// — the client only tokenizes for instant colors; the server owns the
// grammar, the field registry, and value completion.
//
// The tokenizer must stay in sync with Sanctum.Search.Lexer: quoted strings,
// operators (<= >= != < > = : !), parens, pipe, `-` negation, words.

const TOKEN_RE = /(\s+)|("(?:[^"]*)"?)|(<=|>=|!=|[<>=:!])|([()])|(\|)|([^\s"()|:<>=!]+)/g

const KEYWORDS = new Set(["and", "or", "not"])

function tokenize(text) {
  const tokens = []
  let match
  TOKEN_RE.lastIndex = 0
  while ((match = TOKEN_RE.exec(text)) !== null) {
    const [full, ws, str, op, paren, pipe, word] = match
    if (ws != null) tokens.push({type: "ws", text: full})
    else if (str != null) tokens.push({type: "string", text: full})
    else if (op != null) tokens.push({type: "op", text: full})
    else if (paren != null) tokens.push({type: "paren", text: full})
    else if (pipe != null) tokens.push({type: "pipe", text: full})
    else if (word != null) tokens.push({type: "word", text: full})
  }
  return tokens
}

// Second pass: words become field / keyword / number / value / plain text.
function classify(tokens, knownFields) {
  const out = []
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i]
    if (t.type !== "word") {
      out.push({cls: clsFor(t.type), text: t.text})
      continue
    }

    const next = nextNonWs(tokens, i)
    const prev = prevNonWs(tokens, i)
    const lower = t.text.toLowerCase()

    if (next && next.type === "op" && next.text !== "!") {
      const known = knownFields.has(lower.replace(/-/g, "_"))
      out.push({cls: known ? "qi-field" : "qi-field qi-unknown", text: t.text})
    } else if (prev && (prev.type === "op" || prev.type === "pipe")) {
      out.push({cls: /^\d+$/.test(t.text) ? "qi-number" : "qi-value", text: t.text})
    } else if (KEYWORDS.has(lower)) {
      out.push({cls: "qi-keyword", text: t.text})
    } else {
      out.push({cls: null, text: t.text})
    }
  }
  return out
}

function clsFor(type) {
  switch (type) {
    case "string": return "qi-string"
    case "op": return "qi-op"
    case "paren": return "qi-paren"
    case "pipe": return "qi-op"
    default: return null
  }
}

function nextNonWs(tokens, i) {
  for (let j = i + 1; j < tokens.length; j++) if (tokens[j].type !== "ws") return tokens[j]
  return null
}

function prevNonWs(tokens, i) {
  for (let j = i - 1; j >= 0; j--) if (tokens[j].type !== "ws") return tokens[j]
  return null
}

export default {
  mounted() {
    this.input = this.el.querySelector("input")
    this.mirror = document.getElementById(`${this.el.id}-mirror`)
    this.listbox = document.getElementById(`${this.el.id}-listbox`)
    this.knownFields = new Set(JSON.parse(this.el.dataset.fields || "[]"))
    this.items = []
    this.active = -1
    this.suggestTimer = null

    this.paint()

    this.onInput = () => { this.paint(); this.queueSuggest() }
    this.onScroll = () => { this.mirror.scrollLeft = this.input.scrollLeft }
    this.onFocus = () => this.queueSuggest()
    this.onClick = () => this.queueSuggest()
    this.onBlur = () => setTimeout(() => this.close(), 120)
    this.onKeydown = (e) => this.handleKey(e)

    this.input.addEventListener("input", this.onInput)
    this.input.addEventListener("scroll", this.onScroll)
    this.input.addEventListener("focus", this.onFocus)
    this.input.addEventListener("click", this.onClick)
    this.input.addEventListener("blur", this.onBlur)
    this.input.addEventListener("keydown", this.onKeydown)
  },

  // Server patches (e.g. "Clear filters") change the input value outside of
  // typing; repaint the mirror to match.
  updated() {
    this.paint()
  },

  destroyed() {
    clearTimeout(this.suggestTimer)
  },

  paint() {
    const spans = classify(tokenize(this.input.value), this.knownFields)
    this.mirror.textContent = ""
    for (const {cls, text} of spans) {
      if (cls) {
        const span = document.createElement("span")
        span.className = cls
        span.textContent = text
        this.mirror.appendChild(span)
      } else {
        this.mirror.appendChild(document.createTextNode(text))
      }
    }
    this.mirror.scrollLeft = this.input.scrollLeft
  },

  queueSuggest() {
    clearTimeout(this.suggestTimer)
    this.suggestTimer = setTimeout(() => {
      this.pushEvent(
        "suggest",
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
    this.active = -1

    if (this.items.length === 0) return this.close()

    this.listbox.textContent = ""
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

    this.listbox.classList.remove("hidden")
    this.input.setAttribute("aria-expanded", "true")
  },

  close() {
    this.listbox.classList.add("hidden")
    this.listbox.textContent = ""
    this.input.setAttribute("aria-expanded", "false")
    this.input.removeAttribute("aria-activedescendant")
    this.items = []
    this.active = -1
  },

  isOpen() {
    return !this.listbox.classList.contains("hidden") && this.items.length > 0
  },

  setActive(i) {
    this.active = i
    for (const li of this.listbox.children) {
      li.classList.toggle("qi-active", Number(li.dataset.index) === i)
    }
    if (i >= 0) {
      this.input.setAttribute("aria-activedescendant", `${this.el.id}-opt-${i}`)
      this.listbox.children[i]?.scrollIntoView({block: "nearest"})
    }
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
    this.close()

    // Bubble a real input event so the surrounding form's phx-change fires
    // (LiveView's debounced search) — then immediately offer the next step
    // (a field was just completed → its values; a value → next term).
    this.input.dispatchEvent(new Event("input", {bubbles: true}))
  },

  handleKey(e) {
    if (!this.isOpen()) {
      if (e.key === "ArrowDown" && (e.altKey || this.input.value === "")) this.queueSuggest()
      return
    }

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
        if (this.active >= 0) {
          e.preventDefault()
          this.accept(this.active)
        } else {
          this.close()
        }
        break
      case "Tab":
        if (this.active >= 0) {
          e.preventDefault()
          this.accept(this.active)
        } else if (this.items.length > 0) {
          e.preventDefault()
          this.accept(0)
        }
        break
      case "Escape":
        e.preventDefault()
        this.close()
        break
    }
  },
}
