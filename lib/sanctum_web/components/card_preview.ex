defmodule SanctumWeb.Components.CardPreview do
  @moduledoc """
  Hover "card peek" shared by pages with `/cards/:id` links (deck writeups and
  decklists). The CardLinkPreview JS hook watches links under its element and
  pushes `"preview_card"` on hover-intent; a LiveView delegates that event to
  `handle_preview_event/2` and renders `card_preview_popover/1` once at the
  page root. The hook positions and toggles the popover — LiveView only swaps
  the card tile inside it.
  """
  use Phoenix.Component

  import SanctumWeb.Components.CardSideTile

  @doc "Seeds the assigns `card_preview_popover/1` reads; pipe in mount/seed."
  def assign_card_preview(socket) do
    socket
    |> Phoenix.Component.assign(:card_preview, nil)
    # set -> gradient palette for preview tiles, fetched once on first hover
    |> Phoenix.Component.assign(:card_preview_colors, nil)
  end

  @doc """
  Handles the hook's `"preview_card"` event: loads the card's primary face and
  renders the same tile the card pool shows into the popover. The reply tells
  the hook the tile is ready to position; unresolvable ids reply with an error
  so the hook keeps the popover hidden.
  """
  def handle_preview_event(id, socket) do
    actor = socket.assigns[:current_user]
    side_loads = if actor, do: [:owned], else: []

    case Ash.get(Sanctum.Games.Card, id, actor: actor, load: [primary_side: side_loads]) do
      {:ok, %{primary_side: %Sanctum.Games.CardSide{} = side} = card} ->
        colors = socket.assigns.card_preview_colors || Sanctum.Heroes.hero_color_map()

        {:reply, %{},
         socket
         |> Phoenix.Component.assign(:card_preview_colors, colors)
         |> Phoenix.Component.assign(:card_preview, side_view(%{side | card: card}, colors))}

      _ ->
        {:reply, %{error: true}, socket}
    end
  end

  attr :side, :map, default: nil, doc: "display map built by side_view/2; nil until first hover"

  def card_preview_popover(assigns) do
    ~H"""
    <div
      id="card-link-preview"
      class="pointer-events-none fixed left-0 top-0 z-50 hidden w-[480px] max-w-[calc(100vw-16px)]"
    >
      <.card_side_tile :if={@side} side={@side} />
    </div>
    """
  end
end
