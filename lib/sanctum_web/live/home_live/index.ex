defmodule SanctumWeb.HomeLive.Index do
  @moduledoc """
  Public landing page: headline vault stats, the daily player card, and the
  five freshest decks. The games list this page replaced lives at `/games`.
  """

  use SanctumWeb, :live_view

  on_mount {SanctumWeb.LiveUserAuth, :live_user_optional}

  require Ash.Query

  import SanctumWeb.Components.StatTile, only: [stat_tile: 1]

  alias Sanctum.Decks.Stats
  alias Sanctum.Games.CardOfTheDay
  alias SanctumWeb.Components.Card, as: CardComponent
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

      <div class="mt-6 grid items-start gap-6 lg:grid-cols-[300px_1fr]">
        <!-- card of the day -->
        <.panel class="p-4">
          <div class="flex items-baseline justify-between gap-3">
            <h2 class="font-anton text-lg uppercase tracking-[0.05em]">Card of the Day</h2>
            <span class="font-ibm-mono text-[10px] uppercase tracking-[0.2em] text-base-content/45">
              {Calendar.strftime(Date.utc_today(), "%b %-d")}
            </span>
          </div>

          <div
            :if={@home == nil}
            class="mt-3 aspect-[5/7] w-full animate-pulse border-2 border-neutral bg-base-300"
          />

          <.link
            :if={@home != nil && @home.card}
            navigate={~p"/cards/#{@home.card.id}"}
            class="group mt-3 block"
          >
            <div class={[
              "w-full overflow-hidden border-2 border-neutral shadow-comic transition-transform group-hover:-translate-y-0.5",
              (@home.card.landscape? && "aspect-[7/5]") || "aspect-[5/7]"
            ]}>
              <img
                src={@home.card.image_url}
                alt={@home.card.name}
                class="h-full w-full object-cover"
              />
            </div>
            <div class="mt-3 flex items-center gap-2">
              <span class={["size-[8px] rounded-[1px]", @home.card.aspect_bg]}></span>
              <span class="font-barlow-condensed text-[12px] font-bold uppercase tracking-[0.12em] text-base-content/55">
                {@home.card.type_label}
              </span>
            </div>
            <div class="mt-1 font-anton text-[22px] uppercase leading-[0.95] group-hover:text-primary">
              {@home.card.name}
            </div>
            <div
              :if={@home.card.subname}
              class="mt-0.5 font-barlow-condensed text-[13px] text-base-content/55"
            >
              {@home.card.subname}
            </div>
          </.link>

          <p
            :if={@home != nil && @home.card == nil}
            class="mt-3 font-barlow-condensed text-sm text-base-content/55"
          >
            No cards in the vault yet.
          </p>
        </.panel>

        <!-- latest decks -->
        <section>
          <div class="flex items-baseline justify-between gap-3">
            <h2 class="font-anton text-lg uppercase tracking-[0.05em]">Latest Decks</h2>
            <.link
              navigate={~p"/decks"}
              class="font-barlow-condensed text-[13px] font-bold uppercase tracking-[0.08em] text-base-content/55 hover:text-primary"
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
                      "border-2 bg-black px-2 py-0.5 font-barlow-condensed text-[11px] font-bold uppercase tracking-[0.08em]",
                      a.text,
                      a.border
                    ]}
                  >
                    {a.label}
                  </span>
                </div>
                <div class="mt-1.5 break-words font-anton text-[20px] uppercase leading-[0.95]">
                  {deck.title}
                </div>
                <div class="mt-1.5 flex items-center gap-2">
                  <span
                    :if={deck.author}
                    class="font-barlow-condensed text-[13px] font-bold text-primary"
                  >
                    {deck.author}
                  </span>
                  <span class="font-ibm-mono text-[11px] text-base-content/40">
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
            <div class="font-bangers text-[26px] tracking-[0.02em] text-primary">
              No decks in the vault yet
            </div>
          </.panel>
        </section>
      </div>
    </Layouts.app>
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

  defp card_view(nil), do: nil

  defp card_view(card) do
    side = card.primary_side
    aspect = DeckCards.display_aspect(side)

    %{
      id: card.id,
      name: side.name,
      subname: if(side.subname != side.name, do: side.subname),
      type_label: side.type |> to_string() |> String.replace("_", " "),
      aspect_bg: CardComponent.aspect_classes(aspect).bg,
      image_url: side.image_url,
      landscape?: CardComponent.landscape_type?(side.type)
    }
  end

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
