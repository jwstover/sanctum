defmodule SanctumWeb.Components.DeckBuilder do
  @moduledoc """
  Deckbuilder UI pieces: the per-card quantity stepper overlaid on grid
  tiles and (via `SanctumWeb.DeckLive.Build`) the persistent deck bar.
  All controls emit `inc`/`dec` with `phx-value-card-id`; the LiveView owns
  persistence and clamping — the stepper's max only gates the button UI.
  """

  use Phoenix.Component

  import SanctumWeb.CoreComponents, only: [icon: 1]

  @doc """
  Quantity controls for one card. Renders a lone "+" chip at zero and a
  `− n +` cluster above it otherwise. `max` disables (visually) the "+" at
  the card's deck limit; it never blocks the event handler's own clamp.
  """
  attr :card_id, :string, required: true
  attr :qty, :integer, default: 0
  attr :max, :integer, default: 3
  attr :class, :any, default: nil

  def qty_stepper(assigns) do
    ~H"""
    <div class={["pointer-events-none flex items-center justify-end gap-1", @class]}>
      <div
        :if={@qty > 0}
        class="pointer-events-auto flex items-center overflow-hidden rounded-[4px] border border-white/15 bg-base-100/90 backdrop-blur-sm"
      >
        <button
          type="button"
          phx-click="dec"
          phx-value-card-id={@card_id}
          title="Remove a copy"
          class="flex size-7 cursor-pointer items-center justify-center text-white/70 transition-colors hover:text-error sm:size-6"
        >
          <.icon name="hero-minus" class="size-3.5" />
        </button>
        <span class="min-w-5 text-center font-ibm-mono text-[12px] font-bold text-white">
          {@qty}
        </span>
        <button
          type="button"
          phx-click="inc"
          phx-value-card-id={@card_id}
          disabled={@qty >= @max}
          title={(@qty >= @max && "At this card's limit") || "Add a copy"}
          class={[
            "flex size-7 cursor-pointer items-center justify-center transition-colors sm:size-6",
            (@qty >= @max && "cursor-default text-white/25") || "text-white/70 hover:text-success"
          ]}
        >
          <.icon name="hero-plus" class="size-3.5" />
        </button>
      </div>

      <button
        :if={@qty == 0}
        type="button"
        phx-click="inc"
        phx-value-card-id={@card_id}
        title="Add to deck"
        class="pointer-events-auto flex size-7 cursor-pointer items-center justify-center rounded-[4px] border border-white/15 bg-base-100/90 text-white/60 backdrop-blur-sm transition-colors hover:text-success sm:size-6"
      >
        <.icon name="hero-plus" class="size-4" />
      </button>
    </div>
    """
  end
end
