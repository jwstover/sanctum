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
        class="pointer-events-auto flex items-center overflow-hidden border-2 border-neutral bg-base-100/95 shadow-comic-sm backdrop-blur-sm"
      >
        <button
          type="button"
          phx-click="dec"
          phx-value-card-id={@card_id}
          title="Remove a copy"
          class="flex size-9 cursor-pointer items-center justify-center text-white/80 transition-colors hover:bg-error/20 hover:text-error sm:size-8"
        >
          <.icon name="hero-minus" class="size-4" />
        </button>
        <span class="min-w-6 text-center font-ibm-mono text-[14px] font-bold text-success sm:text-[13px]">
          {@qty}
        </span>
        <button
          type="button"
          phx-click="inc"
          phx-value-card-id={@card_id}
          disabled={@qty >= @max}
          title={(@qty >= @max && "At this card's limit") || "Add a copy"}
          class={[
            "flex size-9 cursor-pointer items-center justify-center transition-colors sm:size-8",
            (@qty >= @max && "cursor-default text-white/25") ||
              "text-white/80 hover:bg-success hover:text-success-content"
          ]}
        >
          <.icon name="hero-plus" class="size-4" />
        </button>
      </div>

      <button
        :if={@qty == 0}
        type="button"
        phx-click="inc"
        phx-value-card-id={@card_id}
        title="Add to deck"
        class="pointer-events-auto flex size-9 cursor-pointer items-center justify-center border-2 border-neutral bg-success text-white shadow-comic-sm transition-transform hover:-translate-y-0.5 sm:size-8"
      >
        <.icon name="hero-plus" class="size-5" />
      </button>
    </div>
    """
  end
end
