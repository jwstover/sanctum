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
    values: [nil, :browse, :cards, :guess, :decks, :admin],
    doc: "which top-nav tab to highlight"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="drawer min-h-screen bg-base-100 text-base-content font-barlow-condensed lg:drawer-open">
      <input id="app-drawer" type="checkbox" class="drawer-toggle" />

      <div class="drawer-content relative min-h-screen">
        <div class="pointer-events-none fixed inset-0 z-0 bg-halftone"></div>

        <!-- slim top bar (mobile only) -->
        <header class="sticky top-0 z-30 border-b-[3px] border-neutral bg-base-100/90 backdrop-blur lg:hidden">
          <div class="flex items-center justify-between px-4 py-3.5">
            <a href="/" class="font-bangers text-[28px] leading-none tracking-wide text-primary">
              SANCTUM
            </a>
            <label
              for="app-drawer"
              class="drawer-button flex size-11 cursor-pointer items-center justify-center border-2 border-neutral bg-base-300 text-base-content"
              aria-label="Open menu"
            >
              <.icon name="hero-bars-3" class="size-6" />
            </label>
          </div>
        </header>

        <main class="relative z-10 mx-auto max-w-[1480px] px-4 pb-24 pt-7 sm:px-6">
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
              class="font-bangers text-[28px] leading-none tracking-wide text-primary lg:text-[24px]"
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
          <nav class="mt-6 flex flex-col gap-1.5 lg:mt-4 lg:gap-1">
            <.sidebar_link navigate={~p"/browse"} active={@active_tab == :browse}>
              Packs
            </.sidebar_link>
            <.sidebar_link navigate={~p"/cards"} active={@active_tab == :cards}>
              Cards
            </.sidebar_link>
            <.sidebar_link navigate={~p"/decks"} active={@active_tab == :decks}>
              Decks
            </.sidebar_link>
            <.sidebar_link navigate={~p"/flavor-town"} active={@active_tab == :guess}>
              Flavor Town
            </.sidebar_link>
            <.sidebar_link
              :if={@current_user && @current_user.admin}
              navigate={~p"/admin"}
              active={@active_tab == :admin}
            >
              Admin
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

    <.flash_group flash={@flash} />
    """
  end

  # Unchecks the daisyUI drawer toggle so the slideout closes after
  # navigating on mobile (handled by a window listener in app.js).
  defp close_drawer(js \\ %JS{}) do
    JS.dispatch(js, "sanctum:close-drawer", to: "#app-drawer")
  end

  attr :active, :boolean, default: false
  attr :rest, :global, include: ~w(href navigate patch)
  slot :inner_block, required: true

  # Block-level nav link used inside the sidebar / slideout drawer. Inactive
  # links are quiet text rows; the active one becomes a comic "caption box" —
  # halftone cardstock, hard offset shadow, and a slight tilt.
  defp sidebar_link(assigns) do
    ~H"""
    <.link
      class={[
        "border-2 px-3 py-2 font-barlow-condensed text-[15px] font-bold uppercase tracking-[0.1em] transition-colors lg:px-2.5 lg:py-1.5 lg:text-[13px]",
        (@active && "-rotate-1 border-neutral bg-base-300 bg-halftone text-primary shadow-comic-sm") ||
          "border-transparent text-base-content/55 hover:text-white"
      ]}
      phx-click={close_drawer()}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
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
