// Client-side tokenizer + classifier for the search query language, shared by
// the QueryInput and GlobalSearch hooks. Must stay in sync with
// Sanctum.Search.Lexer: quoted strings, operators (<= >= != < > = : !),
// parens, pipe, `-` negation, words.

const TOKEN_RE = /(\s+)|("(?:[^"]*)"?)|(<=|>=|!=|[<>=:!])|([()])|(\|)|([^\s"()|:<>=!]+)/g

const KEYWORDS = new Set(["and", "or", "not"])

export function tokenize(text) {
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
export function classify(tokens, knownFields) {
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

// Render classified spans into a mirror element.
export function paintMirror(mirror, value, knownFields) {
  const spans = classify(tokenize(value), knownFields)
  mirror.textContent = ""
  for (const {cls, text} of spans) {
    if (cls) {
      const span = document.createElement("span")
      span.className = cls
      span.textContent = text
      mirror.appendChild(span)
    } else {
      mirror.appendChild(document.createTextNode(text))
    }
  }
}
