defmodule SanctumWeb.Components.HandSizeBadge do
  @moduledoc """
  A hero's hand-size indicator — a small "fanned cards" glyph followed by the
  hand-size number, styled to match the white-rimmed comic card frames.

  Three rounded-rect cards fan out from a shared bottom hinge, each with a white
  fill and a dark stroke. Drawn back-to-front, the front cards' strokes read as
  the gaps between the fanned cards — so no masking is needed.
  """
  use Phoenix.Component

  # One card face (rounded rect, width 24), centered on the bottom hinge (50,82).
  # The three copies are tilted around that hinge with `rotate(...)`.
  @card "M 42.5 37 L 57.5 37 A 4.5 4.5 0 0 1 62 41.5 L 62 75.5 A 4.5 4.5 0 0 1 57.5 80 L 42.5 80 A 4.5 4.5 0 0 1 38 75.5 L 38 41.5 A 4.5 4.5 0 0 1 42.5 37 Z"

  @doc """
  Renders the hand-size icon + number.

  ## Examples

      <.hand_size_badge value={5} />
      <.hand_size_badge value={6} class="text-base-content/80" />
  """
  attr :value, :any, default: nil, doc: "hand size shown to the right of the glyph"
  attr :size, :integer, default: 24, doc: "glyph height in px"
  attr :class, :string, default: nil
  attr :rest, :global

  def hand_size_badge(assigns) do
    assigns = assign(assigns, card: @card, width: round(assigns.size * 72 / 52))

    ~H"""
    <span class={["inline-flex items-center gap-1.5 leading-none", @class]} {@rest}>
      <svg width={@width} height={@size} viewBox="14 34 72 52" role="img" aria-label="Hand size">
        <!-- drawn back-to-front left→right, so each card stacks over the one to its left.
             a small rotation + outward shift keeps the fan gentle but well spaced -->
        <path
          d={@card}
          transform="translate(-9 0) rotate(-15 50 82)"
          fill="currentColor"
          stroke="#141418"
          stroke-width="3"
          stroke-linejoin="round"
        />
        <path d={@card} fill="currentColor" stroke="#141418" stroke-width="3" stroke-linejoin="round" />
        <path
          d={@card}
          transform="translate(9 0) rotate(15 50 82)"
          fill="currentColor"
          stroke="#141418"
          stroke-width="3"
          stroke-linejoin="round"
        />
      </svg>
      <span :if={not is_nil(@value)} class="font-elektra-med text-2xl/tight h-6">
        {@value}
      </span>
    </span>
    """
  end
end
