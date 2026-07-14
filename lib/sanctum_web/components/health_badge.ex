defmodule SanctumWeb.Components.HealthBadge do
  @moduledoc """
  The circular hit-point badge from the Champions card frames — a white-rimmed,
  black-ringed disc with an orange/red comic burst and a heavy outlined number.
  Pure SVG (no raster art), modeled on `SanctumWeb.Components.StatBadge`.

  Geometry was tuned against the source card art: a deep-red outer ring around
  a bright orange core, and a loose diagonal splatter of gold ink flecks that
  drifts across the badge from the top-left to the bottom-right, spilling past
  the rim on both ends.
  """
  use Phoenix.Component

  # Tuned geometry (viewBox "25 10 240 220", disc centered 160,120).

  # Splatter: a regularly spaced staggered dot grid, kept only inside a
  # diagonal band running top-left -> bottom-right across the badge so it
  # reads as a cloud drifting over the disc. Dots inside the disc are larger
  # (largest over the red ring); dots past the rim shrink and fade out. Not
  # clipped — the band spills outside the disc on both ends, as in the card
  # art.
  @splatter (for j <- 0..13, i <- 0..14, into: "" do
               x = 30 + i * 15.5 + rem(j, 2) * 7.75
               y = 20 + j * 15.5
               band = abs(x - y - 40) / 1.414
               dist = :math.sqrt((x - 160) ** 2 + (y - 120) ** 2)

               r =
                 cond do
                   band > 52 or dist > 108 -> 0.0
                   dist < 61 -> 3.4
                   dist < 79 -> 3.8
                   dist < 95 -> 2.6
                   true -> 2.0
                 end

               # soften the band edges so the cloud tapers instead of cutting off
               r = if band > 38, do: Float.round(r * 0.7, 1), else: r

               if r > 0 do
                 "<circle cx='#{x}' cy='#{y}' r='#{r}'/>"
               else
                 ""
               end
             end)

  @doc """
  Renders one health badge.

  ## Examples

      <.health_badge value={12} />
      <.health_badge value={3} size={64} />
      <.health_badge value={6} player />
      <.health_badge value="*" bright="#f59b1f" dark="#8f160d" />
  """
  attr :value, :any, default: nil, doc: "number/marker shown in the disc"
  attr :size, :integer, default: 88, doc: "rendered width in px"
  attr :bright, :string, default: "#e38323", doc: "override the orange core color"
  attr :dark, :string, default: "#d01439", doc: "override the red outer-ring color"
  attr :splatter, :string, default: "#d19c2e", doc: "override the splatter fleck color"

  attr :player, :boolean,
    default: false,
    doc: "show a player icon (ChampionsIcons 'v') to the right of the number"

  attr :class, :string, default: nil
  attr :rest, :global

  def health_badge(assigns) do
    # Unique per instance so the internal gradient/filter ids never collide,
    # even when the same badge is rendered more than once on a page.
    uid = "hb#{System.unique_integer([:positive])}"

    assigns =
      assign(assigns,
        uid: uid,
        height: round(assigns.size * 220 / 240),
        flecks: @splatter
      )

    ~H"""
    <svg
      class={@class}
      width={@size}
      height={@height}
      viewBox="25 10 240 220"
      role="img"
      aria-label={"HP #{@value}"}
      style="overflow:visible"
      {@rest}
    >
      <defs>
        <radialGradient id={"fill-#{@uid}"} gradientUnits="userSpaceOnUse" cx="152" cy="110" r="70">
          <stop offset="0%" stop-color="#f5a041" />
          <stop offset="60%" stop-color={@bright} />
          <stop offset="100%" stop-color={@bright} />
        </radialGradient>
        <filter id={"shadow-#{@uid}"} x="-30%" y="-30%" width="160%" height="170%">
          <feDropShadow dx="-2.5" dy="4" stdDeviation="1.2" flood-color="#000" flood-opacity="0.55" />
        </filter>
      </defs>

      <circle cx="160" cy="120" r="98" fill="#fbfbfb" />
      <circle cx="160" cy="120" r="93" fill="#141418" />
      <circle cx="160" cy="120" r="79" fill={@dark} />
      <circle cx="160" cy="120" r="61" fill={"url(#fill-#{@uid})"} />
      <g fill={@splatter}>{Phoenix.HTML.raw(@flecks)}</g>

      <text
        x={if @player, do: "156", else: "160"}
        y="122"
        text-anchor="middle"
        dominant-baseline="central"
        fill="#fff"
        stroke="#101014"
        stroke-width="8"
        stroke-linejoin="round"
        style="font-family:'ElektraMed','Elektra Medium Pro',sans-serif;font-weight:700;font-style:italic;font-size:130px;paint-order:stroke"
        filter={"url(#shadow-#{@uid})"}
      >
        {@value}
        <tspan
          :if={@player}
          dx="4"
          dy="26"
          stroke-width="5"
          style="font-family:'ChampionsIcons';font-style:normal;font-size:64px;paint-order:stroke"
        >
          v
        </tspan>
      </text>
    </svg>
    """
  end
end
