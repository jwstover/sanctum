defmodule SanctumWeb.CardLive.Index do
  use SanctumWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash}>
      <.header>
        Listing Cards
        <:actions>
          <.button navigate={~p"/admin/cards/sync"}>
            <.icon name="hero-arrow-path" /> Sync
          </.button>
          <.button variant="primary" navigate={~p"/admin/cards/new"}>
            <.icon name="hero-plus" /> New Card
          </.button>
        </:actions>
      </.header>

      <div :if={!@loaded?} class="mt-4 space-y-2">
        <div :for={_ <- 1..8} class="h-14 animate-pulse bg-base-300"></div>
      </div>

      <div :if={@loaded?} class="w-full overflow-auto">
        <.table
          id="cards"
          rows={@streams.cards}
          row_click={fn {_id, card} -> JS.navigate(~p"/admin/cards/#{card}") end}
          phx-viewport-bottom={!@end_of_timeline? && "next-page"}
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
              <.link navigate={~p"/admin/cards/#{card}"}>Show</.link>
            </div>

            <.link navigate={~p"/admin/cards/#{card}/edit"}>Edit</.link>
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

  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Manage Cards")
      |> assign(:offset, 0)
      |> assign(:end_of_timeline?, false)
      # loaded? gates the skeleton → table swap once the first page arrives.
      |> assign(:loaded?, false)
      |> assign(:loading?, true)
      |> stream(:cards, [])

    # Skip the first-page query on the static render; load asynchronously once
    # the socket connects so the shell paints immediately.
    socket = if connected?(socket), do: start_load(socket, 0), else: socket

    {:ok, socket}
  end

  @impl true
  def handle_event("next-page", _params, socket) do
    if socket.assigns.end_of_timeline? or socket.assigns.loading? do
      {:noreply, socket}
    else
      {:noreply, start_load(socket, socket.assigns.offset + @page_size)}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    card = Ash.get!(Sanctum.Games.Card, id, actor: socket.assigns.current_user)
    Ash.destroy!(card, actor: socket.assigns.current_user)

    {:noreply, stream_delete(socket, :cards, card)}
  end

  @impl true
  def handle_async(:load_cards, {:ok, %{page: page, offset: offset}}, socket) do
    {:noreply,
     socket
     |> assign(:offset, offset)
     |> assign(:end_of_timeline?, !page.more?)
     |> assign(:loading?, false)
     |> assign(:loaded?, true)
     |> stream(:cards, page.results, at: -1)}
  end

  def handle_async(:load_cards, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:loading?, false)
     |> assign(:loaded?, true)
     |> put_flash(:error, "Couldn’t load cards: #{inspect(reason)}")}
  end

  defp start_load(socket, offset) do
    actor = socket.assigns[:current_user]

    socket
    |> assign(:loading?, true)
    |> start_async(:load_cards, fn ->
      page =
        Sanctum.Games.list_cards!(
          actor: actor,
          load: [:primary_side, :card_sides],
          query: [sort: [base_code: :asc]],
          page: [limit: @page_size, offset: offset]
        )

      %{page: page, offset: offset}
    end)
  end
end
