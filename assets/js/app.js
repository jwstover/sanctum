// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
import * as Sentry from "@sentry/browser"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/sanctum"
import topbar from "../vendor/topbar"
import CardDrag from "./hooks/card-drag";
import DragDrop from "./hooks/drag-drop";
import LayoutHand from "./hooks/layout-hand";
import QueryInput from "./hooks/query-input";
import ResponsivePlaceholder from "./hooks/responsive-placeholder";
import ScrollRestore from "./hooks/scroll-restore";

// Sentry config arrives via meta tags rendered only when a DSN is configured
// (prod). Kept out of an inline <script> so the prod CSP can leave script-src
// at 'self' with no 'unsafe-inline'.
const meta = (name) => document.querySelector(`meta[name='${name}']`)?.getAttribute("content")
const sentryDsn = meta("sentry-dsn")
if (sentryDsn) {
  Sentry.init({
    dsn: sentryDsn,
    environment: meta("sentry-environment") ?? "production",
    release: meta("sentry-release") ?? undefined,
    integrations: [Sentry.browserTracingIntegration()],
    tracesSampleRate: 1.0,
  })
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, CardDrag, DragDrop, LayoutHand, QueryInput, ResponsivePlaceholder, ScrollRestore},
})

// Uncheck the daisyUI drawer toggle when a sidebar link is clicked, so the
// mobile slideout closes across live navigation (checkbox state survives
// LiveView DOM patches).
window.addEventListener("sanctum:close-drawer", e => { e.target.checked = false })

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Register the service worker. Kept here (not as an inline <script> in the
// root layout) so the prod CSP can leave script-src at 'self' with no
// 'unsafe-inline'.
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/sw.js")
    .then(() => console.log("Service Worker registered"))
    .catch((error) => console.log("Service Worker registration failed:", error))
}

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

