defmodule SanctumWeb.CardLive.Index do
  use SanctumWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash}>
      <.header>
        Listing Cards
        <:actions>
          <.button variant="primary" navigate={~p"/cards/new"}>
            <.icon name="hero-plus" /> New Card
          </.button>
        </:actions>
      </.header>

      <div class="w-full overflow-auto">
        <.table
          id="cards"
          rows={@streams.cards}
          row_click={fn {_id, card} -> JS.navigate(~p"/cards/#{card}") end}
        >
          <:col :let={{_id, card}} label="Image">
            <img
              :if={card.primary_side}
              loading="lazy"
              src={card.primary_side.image_url}
              alt={card.primary_side.name}
              class="min-w-[100px] object-contain"
            />
          </:col>
          <:col :let={{_id, card}} label="Name">
            <div>
              <div class="font-medium">{card.primary_side && card.primary_side.name}</div>
              <div :if={card.is_multi_sided} class="text-xs text-gray-500">
                {length(card.card_sides)} sides
              </div>
            </div>
          </:col>
          <:col :let={{_id, card}} label="Base Code">{card.base_code}</:col>
          <:col :let={{_id, card}} label="Primary Code">{card.code}</:col>
          <:col :let={{_id, card}} label="Type">{card.primary_side && card.primary_side.type}</:col>
          <:col :let={{_id, card}} label="Aspect">
            {card.primary_side && card.primary_side.aspect}
          </:col>
          <:col :let={{_id, card}} label="Text">
            <div class="max-w-xs truncate">{card.primary_side && card.primary_side.text}</div>
          </:col>
          <:col :let={{_id, card}} label="Traits">
            {card.primary_side && Enum.join(card.primary_side.traits || [], ", ")}
          </:col>
          <:col :let={{_id, card}} label="Multi-sided">
            <span
              :if={card.is_multi_sided}
              class="inline-flex items-center px-2 py-1 text-xs font-medium text-blue-700 bg-blue-100 rounded-full"
            >
              Multi
            </span>
          </:col>
          <:col :let={{_id, card}} label="Deck Limit">{card.deck_limit}</:col>
          <:col :let={{_id, card}} label="Unique">{card.unique}</:col>
          <:col :let={{_id, card}} label="Set">{card.set}</:col>
          <:col :let={{_id, card}} label="Pack">{card.pack}</:col>

          <:action :let={{_id, card}}>
            <div class="sr-only">
              <.link navigate={~p"/cards/#{card}"}>Show</.link>
            </div>

            <.link navigate={~p"/cards/#{card}/edit"}>Edit</.link>
          </:action>

          <:action :let={{id, card}}>
            <.link
              phx-click={JS.push("delete", value: %{id: card.id}) |> hide("##{id}")}
              data-confirm="Are you sure?"
            >
              Delete
            </.link>
          </:action>
        </.table>
      </div>
    </Layouts.admin>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    cards =
      Sanctum.Games.list_cards!(
        actor: socket.assigns[:current_user],
        load: [:primary_side, :card_sides],
        query: [sort: [base_code: :asc]]
      )

    {:ok,
     socket
     |> assign(:page_title, "Listing Cards")
     |> assign_new(:current_user, fn -> nil end)
     |> stream(:cards, cards)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    card = Ash.get!(Sanctum.Games.Card, id, actor: socket.assigns.current_user)
    Ash.destroy!(card, actor: socket.assigns.current_user)

    {:noreply, stream_delete(socket, :cards, card)}
  end
end
