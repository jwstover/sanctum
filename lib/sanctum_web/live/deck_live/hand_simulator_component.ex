defmodule SanctumWeb.DeckLive.HandSimulatorComponent do
  @moduledoc """
  Opening-hand draw simulator for the deck detail page: draw a hand equal to
  the hero's alter-ego hand size, then resolve the one allowed mulligan
  (discard any selection, draw back up to hand size) plus an unlimited
  "New Hand" reshuffle. All logic lives in `Sanctum.Decks.HandSimulator`; this
  component only tracks the current state and renders it.

  Session-only, like `GuessLive.GameComponent` — nothing here is persisted.
  """
  use SanctumWeb, :live_component

  import SanctumWeb.Components.HandSizeBadge

  alias Sanctum.Decks.HandSimulator

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class={@class}>
      <.panel class="p-4">
        <div class="mb-3 flex items-center gap-2 border-b-2 border-neutral pb-2">
          <div class="font-anton text-lg uppercase tracking-[0.05em]">Opening Hand</div>
          <.hand_size_badge :if={@hand_size} value={@hand_size} size={20} class="text-primary" />
          <div class="ml-auto font-ibm-mono text-xs text-base-content/45">
            <span :if={@state}>{length(@state.pile)} left in deck</span>
          </div>
        </div>

        <div :if={@draw_deck_size == 0} class="font-barlow text-sm italic text-base-content/45">
          No cards in this deck yet.
        </div>

        <div :if={@draw_deck_size > 0 and @state == nil} class="flex flex-col gap-3">
          <div class="font-barlow text-sm text-base-content/60">
            Draw a {@hand_size}-card opening hand from the {@draw_deck_size}-card draw deck, then
            take your one mulligan.
          </div>
          <.button variant="primary" phx-click="draw" phx-target={@myself} class="self-start">
            Draw Opening Hand
          </.button>
        </div>

        <div :if={@state != nil} class="flex flex-col gap-3">
          <div
            :if={@state.mulliganed?}
            class="font-barlow-condensed text-xs font-bold uppercase tracking-[0.08em] text-base-content/45"
          >
            Mulligan used
          </div>
          <div
            :if={!@state.mulliganed?}
            class="font-barlow text-sm text-base-content/60"
          >
            Select cards to discard, then mulligan — you get one shot at this hand.
          </div>

          <div class="grid grid-cols-[repeat(auto-fill,minmax(104px,1fr))] gap-2">
            <button
              :for={c <- @state.hand}
              type="button"
              phx-click={!@state.mulliganed? && "toggle_card"}
              phx-value-copy_id={c.copy_id}
              phx-target={@myself}
              disabled={@state.mulliganed?}
              aria-pressed={to_string(MapSet.member?(@selected, c.copy_id))}
              class={[
                "relative aspect-[236/330] border-2 shadow-comic-sm transition-opacity",
                (MapSet.member?(@selected, c.copy_id) && "border-error opacity-40") ||
                  "border-neutral opacity-100",
                @state.mulliganed? && "cursor-default"
              ]}
            >
              <.mc_card
                name={c.name}
                cost={c.cost}
                aspect={c.aspect_key}
                image_url={c.image_url}
                gradient_from={c.gradient_from}
                gradient_to={c.gradient_to}
                size="md"
                show_cost={false}
              />
              <span
                :if={MapSet.member?(@selected, c.copy_id)}
                class="absolute right-1 top-1 z-[4] flex size-6 items-center justify-center rounded-full bg-error text-white shadow-comic-sm"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </span>
            </button>
          </div>

          <div class="mt-1 flex flex-wrap items-center gap-2">
            <.button
              :if={!@state.mulliganed?}
              variant="primary"
              phx-click="mulligan"
              phx-target={@myself}
              disabled={MapSet.size(@selected) == 0}
            >
              Mulligan ({MapSet.size(@selected)})
            </.button>
            <.button
              :if={!@state.mulliganed? and MapSet.size(@selected) > 0}
              variant="ghost"
              phx-click="clear_selection"
              phx-target={@myself}
            >
              Clear
            </.button>
            <.button variant="ghost" phx-click="new_hand" phx-target={@myself}>
              New Hand
            </.button>
          </div>
        </div>
      </.panel>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    # Initialize derived assigns once — a parent re-render (e.g. the favorite
    # toggle) must not reshuffle an in-progress hand.
    socket =
      socket
      |> assign_new(:class, fn -> nil end)
      |> assign_new(:state, fn -> nil end)
      |> assign_new(:selected, fn -> MapSet.new() end)
      |> assign_new(:draw_deck_size, fn ->
        assigns.card_views
        |> Enum.filter(&(&1.qty > 0 and not &1.permanent))
        |> Enum.sum_by(& &1.qty)
      end)

    {:ok, socket}
  end

  @impl true
  def handle_event("draw", _params, socket) do
    {:noreply, draw_new_hand(socket)}
  end

  def handle_event("toggle_card", %{"copy_id" => copy_id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected, copy_id) do
        MapSet.delete(socket.assigns.selected, copy_id)
      else
        MapSet.put(socket.assigns.selected, copy_id)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, :selected, MapSet.new())}
  end

  def handle_event("mulligan", _params, socket) do
    state = HandSimulator.mulligan(socket.assigns.state, MapSet.to_list(socket.assigns.selected))

    {:noreply,
     socket
     |> assign(:state, state)
     |> assign(:selected, MapSet.new())}
  end

  def handle_event("new_hand", _params, socket) do
    {:noreply, draw_new_hand(socket)}
  end

  defp draw_new_hand(socket) do
    state = HandSimulator.new(socket.assigns.card_views, socket.assigns.hand_size)

    socket
    |> assign(:state, state)
    |> assign(:selected, MapSet.new())
  end
end
