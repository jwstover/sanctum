defmodule SanctumWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SanctumWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_user, Sanctum.Accounts.User, required: false

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :active_tab, :atom,
    default: nil,
    values: [
      nil,
      :home,
      :games,
      :browse,
      :cards,
      :guess,
      :decks,
      :homebrew,
      :stats,
      :profile,
      :admin
    ],
    doc: "which top-nav tab to highlight"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <!-- profile prompt: signed-in users without a username. Sits above the
         drawer so it spans the full viewport (sidebar included). Hidden by
         default; the hook flags <html> (which LiveView never patches, so the
         flag survives DOM updates) unless this browser dismissed the banner
         before (localStorage, keyed per user). -->
    <div
      :if={@current_user && !@current_user.username}
      id="update-profile-banner"
      phx-hook=".ProfileBanner"
      data-user-id={@current_user.id}
      class="relative z-20 hidden border-b-[3px] border-neutral bg-base-300 bg-halftone font-barlow-condensed text-base-content [html[data-show-profile-banner]_&]:block"
    >
      <div class="mx-auto flex w-full max-w-[1480px] flex-wrap items-center gap-x-4 gap-y-2 px-4 py-2.5 sm:px-6">
        <span class="font-bangers text-lg leading-none tracking-wide text-primary">
          Update your profile!
        </span>
        <span class="font-barlow-condensed text-sm font-bold uppercase tracking-[0.08em] text-base-content/60">
          Pick a username to get credit on your decks
        </span>
        <.link
          navigate={~p"/profile"}
          class="ml-auto border-2 border-neutral bg-primary px-3 py-1 font-barlow-condensed text-sm font-bold uppercase tracking-[0.1em] text-primary-content shadow-comic-sm"
        >
          Go to profile
        </.link>
        <button
          type="button"
          data-dismiss
          aria-label="Dismiss"
          class="flex size-8 cursor-pointer items-center justify-center border-2 border-neutral bg-base-100 text-base-content/70 transition-colors hover:text-white"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ProfileBanner">
        export default {
          mounted() {
            this.key = `sanctum:profile-banner-dismissed:${this.el.dataset.userId}`
            if (!localStorage.getItem(this.key)) {
              document.documentElement.setAttribute("data-show-profile-banner", "")
            }
            this.el.querySelector("[data-dismiss]").addEventListener("click", () => {
              localStorage.setItem(this.key, "1")
              document.documentElement.removeAttribute("data-show-profile-banner")
            })
          }
        }
      </script>
    </div>

    <div class="drawer min-h-screen bg-base-100 text-base-content font-barlow-condensed lg:drawer-open">
      <input id="app-drawer" type="checkbox" class="drawer-toggle" />

      <div class="drawer-content relative flex min-h-screen flex-col">
        <div class="pointer-events-none fixed inset-0 z-0 bg-halftone"></div>

        <!-- slim top bar (mobile only) -->
        <header class="sticky top-0 z-30 border-b-[3px] border-neutral bg-base-100/90 backdrop-blur lg:hidden">
          <div class="flex items-center justify-between gap-3 px-4 py-3.5">
            <a href="/" class="font-bangers text-3xl leading-none tracking-wide text-primary">
              SANCTUM
            </a>
            <div class="flex items-center gap-2">
              <button
                type="button"
                phx-click={open_search()}
                class="flex size-11 cursor-pointer items-center justify-center border-2 border-neutral bg-base-300 text-base-content"
                aria-label="Search"
              >
                <.icon name="hero-magnifying-glass" class="size-5" />
              </button>
              <label
                for="app-drawer"
                class="drawer-button flex size-11 cursor-pointer items-center justify-center border-2 border-neutral bg-base-300 text-base-content"
                aria-label="Open menu"
              >
                <.icon name="hero-bars-3" class="size-6" />
              </label>
            </div>
          </div>
        </header>

        <.live_component
          module={SanctumWeb.GlobalSearchComponent}
          id="global-search-bar"
          current_user={@current_user}
        />

        <%!-- No z-index here: a `z-10` would cap every child in a stacking
             context below the sticky header (z-30), so page-level overlays
             (the builder's deck-pane scrim) could never cover the chrome.
             DOM order alone keeps main above the z-0 halftone layer. --%>
        <main class="relative mx-auto w-full max-w-[1480px] flex-1 px-4 pb-24 pt-7 sm:px-6">
          {render_slot(@inner_block)}
        </main>
      </div>

      <!-- sidebar: fixed on lg+, slideout drawer below -->
      <div class="drawer-side z-40">
        <label for="app-drawer" aria-label="Close menu" class="drawer-overlay"></label>
        <aside class="flex min-h-full w-[260px] max-w-[85vw] flex-col border-r-[3px] border-neutral bg-base-100 px-5 py-5 shadow-comic-lg lg:w-[200px] lg:px-4 lg:py-4 lg:shadow-none">
          <div class="flex items-center justify-between border-b-2 border-neutral pb-4 lg:pb-3">
            <a
              href="/"
              class="font-bangers text-3xl leading-none tracking-wide text-primary lg:text-2xl"
            >
              SANCTUM
            </a>
            <label
              for="app-drawer"
              class="flex size-11 cursor-pointer items-center justify-center border-2 border-neutral bg-base-300 text-base-content lg:hidden"
              aria-label="Close menu"
            >
              <.icon name="hero-x-mark" class="size-6" />
            </label>
          </div>
          <nav class="mt-6 flex flex-col flex-1 gap-1.5 lg:mt-4 lg:gap-1">
            <button
              type="button"
              phx-click={open_search()}
              class="hidden cursor-pointer items-center justify-between border-2 border-transparent px-3 py-2 font-barlow-condensed text-base font-bold uppercase tracking-[0.1em] text-base-content/55 transition-colors hover:text-white lg:flex lg:px-2.5 lg:py-1.5 lg:text-sm"
            >
              <span class="flex items-center gap-2">
                <.icon name="hero-magnifying-glass" class="size-3.5" /> Search
              </span>
              <kbd class="border border-base-content/20 px-1 font-ibm-mono text-xs normal-case tracking-normal text-base-content/35">
                ⌘K
              </kbd>
            </button>
            <.sidebar_link navigate={~p"/"} active={@active_tab == :home}>
              Home
            </.sidebar_link>
            <.sidebar_link navigate={~p"/browse"} active={@active_tab == :browse}>
              Packs
            </.sidebar_link>
            <.sidebar_link navigate={~p"/cards"} active={@active_tab == :cards}>
              Cards
            </.sidebar_link>
            <.sidebar_link navigate={~p"/decks"} active={@active_tab == :decks}>
              Decks
            </.sidebar_link>
            <.sidebar_link
              :if={@current_user && @current_user.admin}
              navigate={~p"/homebrew"}
              active={@active_tab == :homebrew}
            >
              Homebrew
            </.sidebar_link>
            <.sidebar_link navigate={~p"/flavor-town"} active={@active_tab == :guess}>
              Flavor Town
            </.sidebar_link>
            <.sidebar_link navigate={~p"/stats"} active={@active_tab == :stats}>
              Stats
            </.sidebar_link>
            <div class="flex-1"></div>
            <.sidebar_link
              :if={@current_user}
              navigate={~p"/profile"}
              active={@active_tab == :profile}
            >
              <div class="flex items-center gap-2">
                <.icon name="hero-user-solid" /> Profile
              </div>
            </.sidebar_link>
            <.sidebar_link
              :if={@current_user && @current_user.admin}
              navigate={~p"/admin"}
              active={@active_tab == :admin}
            >
              <div class="flex items-center gap-2">
                <.icon name="hero-cog-solid" /> Admin
              </div>
            </.sidebar_link>
          </nav>
          <div class="mt-auto flex items-center justify-between border-t-2 border-neutral pt-4">
            <span class="font-ibm-mono text-xs text-base-content/40">
              v{Application.spec(:sanctum, :vsn)}
            </span>
            <.button
              :if={!@current_user}
              variant="primary"
              navigate={~p"/sign-in"}
              phx-click={close_drawer()}
            >
              Sign In
            </.button>
            <.button
              :if={@current_user}
              variant="ghost"
              navigate={~p"/sign-out"}
              phx-click={close_drawer()}
            >
              Sign Out
            </.button>
          </div>
        </aside>
      </div>
    </div>

    <.site_footer />

    <.flash_group flash={@flash} />
    """
  end

  # Unchecks the daisyUI drawer toggle so the slideout closes after
  # navigating on mobile (handled by a window listener in app.js).
  defp close_drawer(js \\ %JS{}) do
    JS.dispatch(js, "sanctum:close-drawer", to: "#app-drawer")
  end

  # Opens the global search overlay (handled by the GlobalSearch hook, which
  # listens for this event on window — same pattern as sanctum:close-drawer).
  defp open_search(js \\ %JS{}) do
    JS.dispatch(js, "sanctum:open-search")
  end

  attr :active, :boolean, default: false
  attr :rest, :global, include: ~w(href navigate patch)
  slot :inner_block, required: true

  # Block-level nav link used inside the sidebar / slideout drawer. Inactive
  # links are quiet text rows; the active one becomes a comic "caption box" —
  # halftone cardstock, hard offset shadow, and a slight tilt.
  #
  # data-scroll-reset marks these as fresh entry points: the ScrollRestore
  # hook clears any saved scroll position for the target path, so section
  # links always land at the top (browser back still restores).
  defp sidebar_link(assigns) do
    ~H"""
    <.link
      class={[
        "border-2 px-3 py-2 font-barlow-condensed text-base font-bold uppercase tracking-[0.1em] transition-colors lg:px-2.5 lg:py-1.5 lg:text-sm",
        (@active && "-rotate-1 border-neutral bg-base-300 bg-halftone text-primary shadow-comic-sm") ||
          "border-transparent text-base-content/55 hover:text-white"
      ]}
      phx-click={close_drawer()}
      data-scroll-reset
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  # Site-wide footer for the standard app shell. Carries the MarvelCDB data
  # attribution and the mandatory Fantasy Flight Games / Marvel copyright
  # disclaimer that fan sites (MarvelCDB, mc4db) surface.
  defp site_footer(assigns) do
    ~H"""
    <footer class="relative border-t-[3px] border-neutral bg-base-100/80">
      <div class="mx-auto w-full max-w-[1480px] px-4 py-8 sm:px-6">
        <div class="flex flex-col gap-3 sm:flex-row sm:items-baseline sm:justify-between">
          <div class="flex items-baseline gap-3">
            <span class="font-bangers text-2xl leading-none tracking-wide text-primary">
              SANCTUM
            </span>
            <span class="font-ibm-mono text-xs text-base-content/40">
              v{Application.spec(:sanctum, :vsn)}
            </span>
          </div>
          <p class="font-ibm-mono text-xs text-base-content/45">
            Much of the card data &amp; imagery is courtesy of <a
              href="https://marvelcdb.com"
              target="_blank"
              rel="noopener noreferrer"
              class="text-base-content/70 underline decoration-dotted underline-offset-2 transition-colors hover:text-primary"
            >
              MarvelCDB
            </a>.
          </p>
        </div>

        <p class="mt-6 max-w-3xl font-barlow-condensed text-sm leading-relaxed text-base-content/40">
          Sanctum is an unofficial, fan-made project. The information presented on this site about
          Marvel Champions: The Card Game, both literal and graphical, is copyrighted by Fantasy
          Flight Games and/or Marvel. This website is not produced, endorsed, supported, or
          affiliated with Fantasy Flight Games or Marvel.
        </p>

        <p class="mt-4 font-ibm-mono text-xs uppercase tracking-[0.18em] text-base-content/30">
          © {Date.utc_today().year} Sanctum · Go play some Champs
        </p>
      </div>
    </footer>
    """
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def game(assigns) do
    ~H"""
    <main class="w-[100vw] h-[100dvh] overflow-hidden bg-blue-900 text-gray-100">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def admin(assigns) do
    ~H"""
    <main class="w-screen h-screen overflow-hidden p-2 flex flex-col">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
