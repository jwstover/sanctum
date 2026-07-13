defmodule SanctumWeb.DeckLive.Show do
  use SanctumWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash}>
      <.header>
        {@deck.title}
        <:subtitle>
          {@deck.hero && @deck.hero.hero_name} — {format_aspects(@deck.aspects)}
        </:subtitle>
        <:actions>
          <.button navigate={~p"/decks"}>
            <.icon name="hero-arrow-left" />
          </.button>
        </:actions>
      </.header>

      <div class="flex-1 min-h-0 overflow-y-auto pr-1">
        <div class="mb-8 p-6 border-2 border-neutral bg-base-200 shadow-comic">
          <h3 class="font-komika text-lg mb-4">Deck Information</h3>
          <.list>
            <:item title="Source">{@deck.source}</:item>
            <:item :if={@deck.mcdb_id} title="MarvelCDB">
              {@deck.mcdb_type}/{@deck.mcdb_id}
            </:item>
            <:item :if={@deck.mcdb_user} title="Author (MarvelCDB user)">
              #{@deck.mcdb_user.mcdb_user_id}
            </:item>
            <:item title="Aspects">{format_aspects(@deck.aspects)}</:item>
            <:item :if={@deck.tags} title="Tags">{@deck.tags}</:item>
            <:item :if={@deck.version} title="Version">{@deck.version}</:item>
            <:item title="Cards">
              {@total_cards} ({length(@deck.deck_cards)} unique)
            </:item>
            <:item :if={@deck.meta && @deck.meta != %{}} title="Raw meta">
              <code class="text-xs bg-base-300 px-2 py-1">{inspect(@deck.meta)}</code>
            </:item>
          </.list>
        </div>

        <div
          :if={@deck.description_md}
          class="mb-8 p-6 border-2 border-neutral bg-base-200 shadow-comic"
        >
          <h3 class="font-komika text-lg mb-2">Description</h3>
          <div class="font-barlow text-[15px] leading-relaxed text-base-content/90 whitespace-pre-wrap">
            {@deck.description_md}
          </div>
        </div>

        <div class="w-full overflow-auto">
          <.table
            id="deck-cards"
            rows={@deck_cards}
            row_click={fn dc -> JS.navigate(~p"/cards/#{dc.card}") end}
          >
            <:col :let={dc} label="Qty">{dc.quantity}</:col>
            <:col :let={dc} label="Name">{dc.card.primary_side && dc.card.primary_side.name}</:col>
            <:col :let={dc} label="Type">{dc.card.primary_side && dc.card.primary_side.type}</:col>
            <:col :let={dc} label="Aspect">
              {dc.card.primary_side && dc.card.primary_side.aspect}
            </:col>
            <:col :let={dc} label="Cost">{dc.card.primary_side && dc.card.primary_side.cost}</:col>
            <:col :let={dc} label="Base Code">{dc.card.base_code}</:col>
            <:col :let={dc} label="Ignore Limit">
              <span :if={dc.ignore_deck_limit}>yes</span>
            </:col>
          </.table>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    deck =
      Sanctum.Decks.get_deck!(id,
        actor: socket.assigns[:current_user],
        load: [:hero, :mcdb_user, deck_cards: [card: [:primary_side]]]
      )

    deck_cards =
      Enum.sort_by(deck.deck_cards, fn dc ->
        {to_string(dc.card.primary_side && dc.card.primary_side.type), dc.card.base_code}
      end)

    total_cards = Enum.sum(Enum.map(deck.deck_cards, & &1.quantity))

    {:ok,
     socket
     |> assign(:page_title, "Deck - #{deck.title}")
     |> assign(:deck, deck)
     |> assign(:deck_cards, deck_cards)
     |> assign(:total_cards, total_cards)}
  end

  defp format_aspects([]), do: "basic"
  defp format_aspects(aspects), do: Enum.map_join(aspects, ", ", &to_string/1)
end
