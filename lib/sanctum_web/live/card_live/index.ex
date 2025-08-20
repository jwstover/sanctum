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
              loading="lazy"
              src={card.image_url}
              alt={card.name}
              class="min-w-[100px] object-contain"
            />
          </:col>
          <:col :let={{_id, card}} label="Name">{card.name}</:col>
          <:col :let={{_id, card}} label="Subname">{card.subname}</:col>
          <:col :let={{_id, card}} label="Code">{card.code}</:col>
          <:col :let={{_id, card}} label="Type">{card.type}</:col>
          <:col :let={{_id, card}} label="Aspect">{card.aspect}</:col>
          <:col :let={{_id, card}} label="Cost">{card.cost}</:col>
          <:col :let={{_id, card}} label="Text">{card.text}</:col>
          <:col :let={{_id, card}} label="Traits">{Enum.join(card.traits || [], ", ")}</:col>
          <:col :let={{_id, card}} label="Attack">{card.attack}</:col>
          <:col :let={{_id, card}} label="Thwart">{card.thwart}</:col>
          <:col :let={{_id, card}} label="Defense">{card.defense}</:col>
          <:col :let={{_id, card}} label="Health">{card.health}</:col>
          <:col :let={{_id, card}} label="Deck Limit">{card.deck_limit}</:col>
          <:col :let={{_id, card}} label="Unique">{card.unique}</:col>
          <:col :let={{_id, card}} label="Permanent">{card.permanent}</:col>
          <:col :let={{_id, card}} label="Hand Size">{card.hand_size}</:col>
          <:col :let={{_id, card}} label="Recover">{card.recover}</:col>
          <:col :let={{_id, card}} label="Stage">{card.stage}</:col>
          <:col :let={{_id, card}} label="Base Threat">{card.base_threat}</:col>
          <:col :let={{_id, card}} label="Escalation Threat">{card.escalation_threat}</:col>
          <:col :let={{_id, card}} label="Boost">{card.boost}</:col>
          <:col :let={{_id, card}} label="Card Set">{card.card_set}</:col>

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
    {:ok,
     socket
     |> assign(:page_title, "Listing Cards")
     |> assign_new(:current_user, fn -> nil end)
     |> stream(:cards, Ash.read!(Sanctum.Games.Card, actor: socket.assigns[:current_user]))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    card = Ash.get!(Sanctum.Games.Card, id, actor: socket.assigns.current_user)
    Ash.destroy!(card, actor: socket.assigns.current_user)

    {:noreply, stream_delete(socket, :cards, card)}
  end
end
