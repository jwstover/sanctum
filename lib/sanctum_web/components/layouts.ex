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
    <div class="relative min-h-screen bg-base-100 text-base-content font-barlow-condensed">
      <div class="pointer-events-none fixed inset-0 z-0 bg-halftone"></div>

      <!-- sticky top bar -->
      <header class="sticky top-0 z-30 border-b-[3px] border-neutral bg-base-100/90 backdrop-blur">
        <div class="mx-auto flex max-w-[1480px] items-center gap-3 px-4 py-3.5 sm:gap-6 sm:px-6">
          <a
            href="/"
            class="font-bangers text-[28px] leading-none tracking-wide text-primary sm:text-[34px]"
          >
            SANCTUM
          </a>
          <nav class="hidden h-[34px] items-end gap-5 sm:flex">
            <.nav_tab navigate={~p"/browse"} active={@active_tab == :browse}>Browse</.nav_tab>
            <.nav_tab navigate={~p"/cards"} active={@active_tab == :cards}>Card Pool</.nav_tab>
            <.nav_tab navigate={~p"/decks"} active={@active_tab == :decks}>Decks</.nav_tab>
            <.nav_tab navigate={~p"/flavor-town"} active={@active_tab == :guess}>
              Flavor Town
            </.nav_tab>
            <.nav_tab
              :if={@current_user && @current_user.admin}
              navigate={~p"/admin"}
              active={@active_tab == :admin}
            >
              Admin
            </.nav_tab>
          </nav>
          <div class="ml-auto hidden items-center gap-4 sm:flex">
            <span class="font-ibm-mono text-xs text-base-content/40">
              v{Application.spec(:sanctum, :vsn)}
            </span>
            <.button :if={!@current_user} variant="primary" navigate={~p"/sign-in"}>Sign In</.button>
          </div>

          <!-- hamburger (mobile only) -->
          <button
            type="button"
            class="ml-auto flex size-11 items-center justify-center border-2 border-neutral bg-base-300 text-base-content sm:hidden"
            phx-click={open_drawer()}
            aria-label="Open menu"
          >
            <.icon name="hero-bars-3" class="size-6" />
          </button>
        </div>
      </header>

      <!-- mobile slideout drawer -->
      <div
        id="mobile-nav-overlay"
        class="fixed inset-0 z-40 hidden bg-black/70 sm:hidden"
        phx-click={close_drawer()}
        aria-hidden="true"
      >
      </div>
      <div
        id="mobile-nav-panel"
        class="fixed inset-y-0 left-0 z-50 hidden w-[80%] max-w-[300px] translate-x-0 flex-col border-r-[3px] border-neutral bg-base-100 px-6 py-5 shadow-comic-lg sm:hidden"
      >
        <div class="flex items-center justify-between border-b-2 border-neutral pb-4">
          <span class="font-bangers text-[28px] leading-none tracking-wide text-primary">
            SANCTUM
          </span>
          <button
            type="button"
            class="flex size-11 items-center justify-center border-2 border-neutral bg-base-300 text-base-content"
            phx-click={close_drawer()}
            aria-label="Close menu"
          >
            <.icon name="hero-x-mark" class="size-6" />
          </button>
        </div>
        <nav class="mt-6 flex flex-col gap-1">
          <.drawer_link navigate={~p"/browse"} active={@active_tab == :browse}>Browse</.drawer_link>
          <.drawer_link navigate={~p"/cards"} active={@active_tab == :cards}>Card Pool</.drawer_link>
          <.drawer_link navigate={~p"/decks"} active={@active_tab == :decks}>Decks</.drawer_link>
          <.drawer_link navigate={~p"/flavor-town"} active={@active_tab == :guess}>Flavor Town</.drawer_link>
          <.drawer_link
            :if={@current_user && @current_user.admin}
            navigate={~p"/admin"}
            active={@active_tab == :admin}
          >
            Admin
          </.drawer_link>
        </nav>
        <div class="mt-auto flex items-center justify-between border-t-2 border-neutral pt-4">
          <span class="font-ibm-mono text-xs text-base-content/40">
            v{Application.spec(:sanctum, :vsn)}
          </span>
          <.button :if={!@current_user} variant="primary" navigate={~p"/sign-in"}>Sign In</.button>
        </div>
      </div>

      <main class="relative z-10 mx-auto max-w-[1480px] px-4 pb-24 pt-7 sm:px-6">
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  # Slide the mobile drawer + overlay in from the left.
  defp open_drawer(js \\ %JS{}) do
    js
    |> JS.show(
      to: "#mobile-nav-overlay",
      transition: {"transition-opacity ease-out duration-200", "opacity-0", "opacity-100"}
    )
    |> JS.show(
      to: "#mobile-nav-panel",
      display: "flex",
      transition:
        {"transition-transform ease-out duration-200", "-translate-x-full", "translate-x-0"}
    )
  end

  defp close_drawer(js \\ %JS{}) do
    js
    |> JS.hide(
      to: "#mobile-nav-overlay",
      transition: {"transition-opacity ease-in duration-150", "opacity-100", "opacity-0"}
    )
    |> JS.hide(
      to: "#mobile-nav-panel",
      transition:
        {"transition-transform ease-in duration-150", "translate-x-0", "-translate-x-full"}
    )
  end

  attr :active, :boolean, default: false
  attr :rest, :global, include: ~w(href navigate patch)
  slot :inner_block, required: true

  defp nav_tab(assigns) do
    ~H"""
    <.link
      class={[
        "pb-[3px] text-[13px] font-bold uppercase tracking-[0.13em] transition-colors",
        (@active && "border-b-[3px] border-primary text-primary") ||
          "text-base-content/55 hover:text-white"
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :active, :boolean, default: false
  attr :rest, :global, include: ~w(href navigate patch)
  slot :inner_block, required: true

  # Block-level nav link used inside the mobile slideout drawer.
  defp drawer_link(assigns) do
    ~H"""
    <.link
      class={[
        "border-2 px-4 py-3 font-barlow-condensed text-[16px] font-bold uppercase tracking-[0.1em] transition-colors",
        (@active && "border-transparent bg-primary text-primary-content") ||
          "border-neutral bg-base-300 text-base-content hover:text-white"
      ]}
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
