// Restores the window scroll position when the user returns to a page (browser
// back, or an explicit "back to the list" link). LiveView's built-in scroll
// restoration can't help on these pages: content loads asynchronously after
// mount — and the infinite-scroll lists only load their first page — so the
// old scroll height doesn't exist yet when history pops.
//
// How it works:
//   * while mounted, every scroll (rAF-throttled) saves {y, offset} to
//     sessionStorage keyed by pathname + search; `offset` is the page's
//     infinite-scroll offset, mirrored via data-offset on the hook element
//   * on the next mount at the same URL, push "restore-scroll" so the server
//     can reload pages 0..offset in one query, then scroll back to y when it
//     confirms with "sanctum:scroll-restore" (after the content has rendered)
//   * links marked data-scroll-reset (the sidebar nav) clear any saved
//     position for their target path, so section links always start at the
//     top while back/return navigation still restores
//
// Entries are per-tab (sessionStorage) and are only cleared by
// data-scroll-reset clicks; a stale entry at worst restores to a position the
// user last held on that exact URL.

const PREFIX = "sanctum:scroll:"

const storageKey = () => PREFIX + window.location.pathname + window.location.search

// Set when a data-scroll-reset link is clicked, so trailing scroll events
// (e.g. trackpad inertia, or the browser clamping when the old page's content
// is torn down) can't re-save a position we just cleared. Lifted again on the
// next hook mount.
let suppressSave = false

// Target path of a data-scroll-reset click. LiveView doesn't scroll to top on
// live navigation, so when the next mount is at this path we force it there —
// otherwise the browser clamps the old scroll depth against the fresh first
// page and immediately re-triggers viewport loads.
let freshNavPath = null

document.addEventListener("click", (e) => {
  const link = e.target.closest?.("a[data-scroll-reset]")
  if (!link || !link.href) return

  suppressSave = true
  freshNavPath = new URL(link.href, window.location.origin).pathname
  for (let i = sessionStorage.length - 1; i >= 0; i--) {
    const key = sessionStorage.key(i)
    if (key === PREFIX + freshNavPath || key?.startsWith(PREFIX + freshNavPath + "?")) {
      sessionStorage.removeItem(key)
    }
  }
})

export default {
  mounted() {
    const fresh = freshNavPath === window.location.pathname
    freshNavPath = null
    suppressSave = false
    if (fresh) window.scrollTo(0, 0)
    this.ticking = false

    this.onScroll = () => {
      if (this.ticking) return
      this.ticking = true
      requestAnimationFrame(() => {
        this.ticking = false
        if (suppressSave) return
        const offset = parseInt(this.el.dataset.offset ?? "0", 10) || 0
        sessionStorage.setItem(storageKey(), JSON.stringify({y: window.scrollY, offset}))
      })
    }
    window.addEventListener("scroll", this.onScroll, {passive: true})

    // An explicit URL fragment (e.g. a global-search set link landing on
    // /browse/:pack#<set_code>) wins over a saved scroll position.
    if (window.location.hash) return

    const saved = sessionStorage.getItem(storageKey())
    if (!saved) return

    let entry
    try {
      entry = JSON.parse(saved)
    } catch {
      sessionStorage.removeItem(storageKey())
      return
    }

    const y = entry.y ?? 0
    if (y <= 0 && !(entry.offset > 0)) return

    this.handleEvent("sanctum:scroll-restore", () => {
      // rAF so the scroll lands after the confirming diff has been painted.
      requestAnimationFrame(() => window.scrollTo(0, y))
    })
    this.pushEvent("restore-scroll", {offset: entry.offset ?? 0})
  },

  destroyed() {
    window.removeEventListener("scroll", this.onScroll)
  },
}
