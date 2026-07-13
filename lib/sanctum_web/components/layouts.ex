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
    values: [nil, :cards, :decks],
    doc: "which top-nav tab to highlight"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="relative min-h-screen bg-base-100 text-base-content font-barlow-condensed">
      <div class="pointer-events-none fixed inset-0 z-0 bg-halftone"></div>

      <!-- sticky top bar -->
      <header class="sticky top-0 z-30 border-b-[3px] border-neutral bg-base-100/90 backdrop-blur">
        <div class="mx-auto flex max-w-[1480px] items-center gap-6 px-6 py-3.5">
          <a href="/" class="font-bangers text-[34px] leading-none tracking-wide text-primary">
            SANCTUM
          </a>
          <nav class="flex h-[34px] items-end gap-5">
            <.nav_tab navigate={~p"/cards"} active={@active_tab == :cards}>Card Pool</.nav_tab>
            <span
              class="cursor-default pb-[3px] text-[13px] font-bold uppercase tracking-[0.13em] text-base-content/25"
              title="Coming soon"
            >
              Decks
            </span>
          </nav>
          <div class="ml-auto flex items-center gap-4">
            <span class="font-ibm-mono text-xs text-base-content/40">
              v{Application.spec(:sanctum, :vsn)}
            </span>
            <.button :if={!@current_user} variant="primary" navigate={~p"/sign-in"}>Sign In</.button>
          </div>
        </div>
      </header>

      <main class="relative z-10 mx-auto max-w-[1480px] px-6 pb-24 pt-7">
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
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
