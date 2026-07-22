defmodule SanctumWeb.HomeLive.Index do
  @moduledoc """
  Public landing page: headline vault stats, the daily player card, and the
  five freshest decks. The games list this page replaced lives at `/games`.
  """

  use SanctumWeb, :live_view

  on_mount {SanctumWeb.LiveUserAuth, :live_user_optional}

  require Ash.Query

  import SanctumWeb.Components.CardSideTile, only: [card_side_tile: 1]
  import SanctumWeb.Components.StatTile, only: [stat_tile: 1]

  alias Sanctum.Decks.Stats
  alias Sanctum.Games.CardOfTheDay
  alias SanctumWeb.Components.CardSideTile
  alias SanctumWeb.Components.DeckCards
  alias SanctumWeb.Timezone

  @deck_count 5

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:home}>
      <!-- headline stats -->
      <div :if={@home == nil} class="grid grid-cols-2 gap-3 sm:max-w-md">
        <div :for={_ <- 1..2} class="h-20 animate-pulse border-[3px] border-neutral bg-base-300" />
      </div>

      <div :if={@home != nil} class="grid grid-cols-2 gap-3 sm:max-w-md">
        <.stat_tile label="Decks" value={@home.totals.decks} color="text-primary" />
        <.stat_tile
          label="Decks Added this Month"
          value={@home.totals.this_month}
          color="text-success"
        />
      </div>

      <div class="mt-6 grid items-start gap-6 lg:grid-cols-[minmax(0,480px)_1fr]">
        <!-- card of the day -->
        <section>
          <div class="flex items-baseline justify-between gap-3">
            <h2 class="font-anton text-lg uppercase tracking-[0.05em]">Card of the Day</h2>
            <span class="font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/45">
              {Calendar.strftime(Date.utc_today(), "%b %-d")}
            </span>
          </div>

          <div
            :if={@home == nil}
            class="mt-3 h-[280px] animate-pulse border-2 border-neutral bg-base-300"
          />

          <div :if={@home != nil && @home.card} class="mt-3">
            <.card_side_tile side={@home.card} navigate={~p"/cards/#{@home.card.card_id}"} />
          </div>

          <.panel
            :if={@home != nil && @home.card == nil}
            class="mt-3 border-dashed !border-[#2a2a30] px-6 py-10 text-center !shadow-none"
          >
            <div class="font-bangers text-2xl tracking-[0.02em] text-primary">
              No cards in the vault yet
            </div>
          </.panel>

          <!-- embedded Flavor Town: today's puzzle, playable in place -->
          <h2 class="mt-6 font-anton text-lg uppercase tracking-[0.05em]">Flavor Town</h2>
          <div class="mt-3">
            <.live_component
              module={SanctumWeb.GuessLive.GameComponent}
              id="home-flavor-game"
              mode={:embedded}
            />
          </div>
        </section>

        <!-- latest decks -->
        <section>
          <div class="flex items-baseline justify-between gap-3">
            <h2 class="font-anton text-lg uppercase tracking-[0.05em]">Latest Decks</h2>
            <.link
              navigate={~p"/decks"}
              class="font-barlow-condensed text-sm font-bold uppercase tracking-[0.08em] text-base-content/55 hover:text-primary"
            >
              Browse all decks →
            </.link>
          </div>

          <div :if={@home == nil} class="mt-3 flex flex-col gap-3">
            <div
              :for={_ <- 1..@deck_count}
              class="h-[104px] animate-pulse border-2 border-neutral bg-base-300"
            />
          </div>

          <div :if={@home != nil} class="mt-3 flex flex-col gap-3">
            <.link
              :for={deck <- @home.decks}
              navigate={~p"/decks/#{deck.id}"}
              class="mc-tile flex items-center gap-3 border-2 border-neutral bg-base-200 p-3 shadow-comic sm:gap-4"
            >
              <div class="h-[110px] w-[79px] flex-none border-2 border-neutral shadow-comic-sm">
                <.mc_card
                  name={deck.hero_name}
                  aspect={:hero}
                  image_url={deck.identity_image}
                  gradient_from={deck.gradient_from}
                  gradient_to={deck.gradient_to}
                  size="sm"
                  show_cost={false}
                />
              </div>

              <div class="min-w-0 flex-1">
                <div class="flex flex-wrap items-center gap-1.5">
                  <span
                    :for={a <- deck.aspects}
                    class={[
                      "border-2 bg-black px-2 py-0.5 font-barlow-condensed text-xs font-bold uppercase tracking-[0.08em]",
                      a.text,
                      a.border
                    ]}
                  >
                    {a.label}
                  </span>
                </div>
                <div class="mt-1.5 break-words font-anton text-xl uppercase leading-[0.95]">
                  {deck.title}
                </div>
                <div class="mt-1.5 flex items-center gap-2">
                  <span
                    :if={deck.author}
                    class="font-barlow-condensed text-sm font-bold text-primary"
                  >
                    {deck.author}
                  </span>
                  <span class="font-ibm-mono text-xs text-base-content/40">
                    {deck.updated}
                  </span>
                </div>
              </div>
            </.link>
          </div>

          <.panel
            :if={@home != nil && @home.decks == []}
            class="mt-3 border-dashed !border-[#2a2a30] px-6 py-10 text-center !shadow-none"
          >
            <div class="font-bangers text-2xl tracking-[0.02em] text-primary">
              No decks in the vault yet
            </div>
          </.panel>
        </section>
      </div>

      <!-- about: full-width band below the grid -->
      <section class="mt-10">
        <h2 class="font-anton text-lg uppercase tracking-[0.05em]">About Sanctum</h2>

        <.panel class="space-y-8 relative mt-3 overflow-hidden bg-halftone text-lg px-5 py-7 sm:px-8 sm:py-8">
          <div class="space-y-4">
            <.about_heading>Another deck-builder for Marvel Champions?</.about_heading>

            <p>
              There are already some great tools for building decks for Marvel Champions.
              The big one is obviously <.about_link href="https://marvelcdb.com">MarvelCDB</.about_link>, but there are also
              sites like <.about_link href="https://mcquick.pages.dev/">MCQuick</.about_link>
              and <.about_link href="https://mc4db.merlindumesnil.net/">MC4DB</.about_link>.
              Sanctum is another alternative, but tries to maintain parity with MarvelCDB, the community standard.
            </p>
          </div>

          <div class="space-y-4">
            <.about_heading>Two-way Sync</.about_heading>

            <p>
              Public decks created on MarvelCDB are automatically synced over to this app. Essentially every public deck on MarvelCDB, you'll also find here.
              Once deckbuilding is more fleshed out here, the goal is to also allow publishing decks created in Sanctum back to MCDB. Thus using one over the other is really
              just a personal preference and you can freely swap between the two.
            </p>
          </div>

          <div class="space-y-4">
            <.about_heading>Fast as Quicksilver</.about_heading>

            <p>
              A key priority as I'm building this app is speed. I want the entire application to feel snappy, to the point
              where you should not notice the app slowing you down. If you do find certain searches or pages are slow to load
              let me know by opening an issue on <.about_link href="https://github.com/jwstover/sanctum/issues">GitHub</.about_link>.
            </p>
          </div>

          <div class="space-y-4">
            <.about_heading>Custom Content</.about_heading>

            <p>
              There is a large and amazing custom content community for this game. However, I have found that
              it is a little difficult to find all of the custom content that is available because it's scattered
              across Discord servers, forums, and Google Drives. One of my main motivations for starting this project
              was to build a home for all custom content. A place where creators can store and share their work with tools
              to support versioning, validation, testing, and eventually release to the wider community. Plus that custom content
              will be available for use in deck-building if you so desire.
            </p>
          </div>
        </.panel>
      </section>
    </Layouts.app>
    """
  end

  # Comic caption-box heading for the About band's sections.
  slot :inner_block, required: true

  defp about_heading(assigns) do
    ~H"""
    <div class="inline-block -rotate-1 border-2 border-neutral bg-primary px-3.5 py-1.5 font-bangers text-2xl leading-none tracking-[0.02em] text-primary-content shadow-comic-sm">
      {render_slot(@inner_block)}
    </div>
    """
  end

  # External link in the About prose — new tab, the footer's dotted-underline
  # treatment in the accent color.
  attr :href, :string, required: true
  slot :inner_block, required: true

  defp about_link(assigns) do
    ~H"""
    <a
      href={@href}
      target="_blank"
      rel="noopener noreferrer"
      class="text-primary underline decoration-dotted underline-offset-2 transition-colors hover:text-primary/75"
    >
      {render_slot(@inner_block)}
    </a>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Home")
      |> assign(:deck_count, @deck_count)
      # nil until loaded — drives the skeletons.
      |> assign(:home, nil)

    # Defer the queries past the static render so the shell paints immediately
    # (same pattern as the stats page).
    socket =
      if connected?(socket) do
        timezone = socket.assigns.timezone
        start_async(socket, :load_home, fn -> load_home(timezone) end)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_async(:load_home, {:ok, home}, socket) do
    {:noreply, assign(socket, :home, home)}
  end

  def handle_async(:load_home, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:home, %{
       totals: %{decks: 0, this_month: 0, cards: 0, heroes: 0, villains: 0},
       card: nil,
       decks: []
     })
     |> put_flash(:error, "Couldn’t load the homepage: #{inspect(reason)}")}
  end

  defp load_home(timezone) do
    %{
      totals: Stats.totals(),
      card: card_view(CardOfTheDay.for_date()),
      decks: Enum.map(newest_decks(), &deck_view(&1, timezone))
    }
  end

  # The deck browser's :browse read in its default "Newest" order — the
  # homepage list matches page one of /decks.
  defp newest_decks do
    Sanctum.Decks.Deck
    |> Ash.Query.for_read(:browse, %{})
    |> Ash.read!(page: [limit: @deck_count])
    |> Map.get(:results)
  end

  # The pool's dossier-tile display map. Daily-pool cards are never
  # hero-ownership, so no hero-color palette is needed for the gradient.
  defp card_view(nil), do: nil
  defp card_view(card), do: CardSideTile.side_view(%{card.primary_side | card: card}, %{})

  defp deck_view(deck, timezone) do
    hero = deck.hero
    author = DeckCards.author(deck)
    {gradient_from, gradient_to} = DeckCards.hero_gradient(hero)

    %{
      id: deck.id,
      title: deck.title,
      hero_name: hero.display_name,
      identity_image: DeckCards.identity_image(hero),
      gradient_from: gradient_from,
      gradient_to: gradient_to,
      aspects: DeckCards.aspect_badges(deck.aspects),
      author: author && author.name,
      updated: format_date(deck.mcdb_date_update || deck.updated_at, timezone)
    }
  end

  defp format_date(%DateTime{} = dt, timezone),
    do: dt |> Timezone.to_local(timezone) |> Calendar.strftime("%b %-d, %Y")

  defp format_date(_value, _timezone), do: ""
end
