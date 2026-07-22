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

  `size` fits the control to its tile: `"md"` for the browse grid, `"sm"`
  for the compact tiles in the deck panel.
  """
  attr :card_id, :string, required: true
  attr :qty, :integer, default: 0
  attr :max, :integer, default: 3
  attr :size, :string, default: "md", values: ~w(md sm)
  attr :class, :any, default: nil

  def qty_stepper(assigns) do
    # Mobile buttons hit the 44px-target convention (size-11); desktop stays
    # compact past the `sm` breakpoint.
    assigns =
      assign(assigns,
        button_class: (assigns.size == "md" && "size-11 sm:size-8") || "size-9 sm:size-6",
        icon_class: (assigns.size == "md" && "size-5 sm:size-4") || "size-4 sm:size-3.5",
        add_icon_class: (assigns.size == "md" && "size-6 sm:size-5") || "size-5 sm:size-4",
        count_class:
          (assigns.size == "md" && "min-w-7 text-base sm:min-w-6 sm:text-sm") ||
            "min-w-6 text-sm sm:min-w-5 sm:text-xs"
      )

    ~H"""
    <div class={["pointer-events-none flex items-center justify-end gap-1", @class]}>
      <div
        :if={@qty > 0}
        class="pointer-events-auto flex items-center overflow-hidden border-2 border-neutral bg-base-100/95 shadow-comic-sm backdrop-blur-sm"
      >
        <button
          type="button"
          data-haptic
          phx-click="dec"
          phx-value-card-id={@card_id}
          title="Remove a copy"
          class={[
            "flex cursor-pointer items-center justify-center text-white/80 transition-colors hover:bg-error/20 hover:text-error",
            @button_class
          ]}
        >
          <.icon name="hero-minus" class={@icon_class} />
        </button>
        <span class={["text-center font-ibm-mono font-bold text-success", @count_class]}>
          {@qty}
        </span>
        <button
          type="button"
          data-haptic
          phx-click="inc"
          phx-value-card-id={@card_id}
          disabled={@qty >= @max}
          title={(@qty >= @max && "At this card's limit") || "Add a copy"}
          class={[
            "flex cursor-pointer items-center justify-center transition-colors",
            @button_class,
            (@qty >= @max && "cursor-default text-white/25") ||
              "text-white/80 hover:bg-success hover:text-success-content"
          ]}
        >
          <.icon name="hero-plus" class={@icon_class} />
        </button>
      </div>

      <button
        :if={@qty == 0}
        type="button"
        data-haptic
        phx-click="inc"
        phx-value-card-id={@card_id}
        title="Add to deck"
        class={[
          "pointer-events-auto flex cursor-pointer items-center justify-center border-2 border-neutral bg-success text-white shadow-comic-sm transition-transform hover:-translate-y-0.5",
          @button_class
        ]}
      >
        <.icon name="hero-plus" class={@add_icon_class} />
      </button>
    </div>
    """
  end

  @doc """
  Invisible mount point wiring haptic feedback to every element carrying
  `data-haptic`, via one delegated listener. Progressive enhancement: the
  Vibration API works on Android Chrome; iOS Safari exposes no web haptics
  API, so it degrades to nothing there.
  """
  def haptics(assigns) do
    ~H"""
    <div id="haptics" phx-hook=".Haptics"></div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Haptics">
      export default {
        mounted() {
          this.onDown = (e) => {
            if (e.target.closest("[data-haptic]")) navigator.vibrate?.(10)
          }
          document.addEventListener("pointerdown", this.onDown, {passive: true})
        },
        destroyed() {
          document.removeEventListener("pointerdown", this.onDown)
        }
      }
    </script>
    """
  end
end
