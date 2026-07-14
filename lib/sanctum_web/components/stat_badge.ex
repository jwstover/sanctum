defmodule SanctumWeb.Components.StatBadge do
  @moduledoc """
  The comic "starburst" stat badge — the THW / ATK / DEF / SCH / HP markers
  from the Champions card frames, rebuilt as pure SVG (no raster art) so they
  stay crisp at any size and recolor per stat through two colors.

  Geometry was tuned against the source card art: a 7-point star (aspect ~1.3,
  shallow notches, concave arcs), a bottom-left halftone gradient, a heavy
  outlined number, and a full-width nameplate trapezoid. The star tilts for
  comic energy; the nameplate and both bits of text stay flat.
  """
  use Phoenix.Component

  # Tuned geometry (viewBox "-30 0 260 300", star centered ~100,110).
  @tilt -9
  @burst "M 100.0,32.0 Q 113.0,56.1 130.8,60.8 Q 147.6,67.7 179.3,61.4 Q 165.0,83.4 169.2,97.9 Q 174.0,112.3 198.9,127.4 Q 167.7,132.5 155.5,144.0 Q 142.8,154.9 144.0,180.3 Q 118.7,163.0 100.0,164.6 Q 81.3,163.0 56.0,180.3 Q 57.2,154.9 44.5,144.0 Q 32.3,132.5 1.1,127.4 Q 26.0,112.3 30.8,97.9 Q 35.0,83.4 20.7,61.4 Q 52.4,67.7 69.2,60.8 Q 87.0,56.1 100.0,32.0 Z"

  # Halftone: a fixed dot grid whose radius grows toward the bottom-left and
  # fades to nothing toward the top. Precomputed (see priv gen) and clipped to
  # the star at render time.
  @dots "<circle cx='2.0' cy='34.0' r='1.1'/><circle cx='13.5' cy='34.0' r='1.1'/><circle cx='25.0' cy='34.0' r='1.0'/><circle cx='7.8' cy='45.5' r='1.2'/><circle cx='19.2' cy='45.5' r='1.1'/><circle cx='30.8' cy='45.5' r='1.1'/><circle cx='42.2' cy='45.5' r='1.0'/><circle cx='2.0' cy='57.0' r='1.6'/><circle cx='13.5' cy='57.0' r='1.6'/><circle cx='25.0' cy='57.0' r='1.5'/><circle cx='36.5' cy='57.0' r='1.5'/><circle cx='48.0' cy='57.0' r='1.4'/><circle cx='59.5' cy='57.0' r='1.4'/><circle cx='71.0' cy='57.0' r='1.3'/><circle cx='82.5' cy='57.0' r='1.3'/><circle cx='94.0' cy='57.0' r='1.2'/><circle cx='105.5' cy='57.0' r='1.1'/><circle cx='117.0' cy='57.0' r='1.1'/><circle cx='128.5' cy='57.0' r='1.0'/><circle cx='7.8' cy='68.5' r='2.1'/><circle cx='19.2' cy='68.5' r='2.0'/><circle cx='30.8' cy='68.5' r='2.0'/><circle cx='42.2' cy='68.5' r='1.9'/><circle cx='53.8' cy='68.5' r='1.9'/><circle cx='65.2' cy='68.5' r='1.8'/><circle cx='76.8' cy='68.5' r='1.8'/><circle cx='88.2' cy='68.5' r='1.7'/><circle cx='99.8' cy='68.5' r='1.6'/><circle cx='111.2' cy='68.5' r='1.6'/><circle cx='122.8' cy='68.5' r='1.5'/><circle cx='134.2' cy='68.5' r='1.5'/><circle cx='145.8' cy='68.5' r='1.4'/><circle cx='157.2' cy='68.5' r='1.4'/><circle cx='168.8' cy='68.5' r='1.3'/><circle cx='180.2' cy='68.5' r='1.2'/><circle cx='191.8' cy='68.5' r='1.2'/><circle cx='203.2' cy='68.5' r='1.2'/><circle cx='2.0' cy='80.0' r='2.5'/><circle cx='13.5' cy='80.0' r='2.5'/><circle cx='25.0' cy='80.0' r='2.4'/><circle cx='36.5' cy='80.0' r='2.4'/><circle cx='48.0' cy='80.0' r='2.3'/><circle cx='59.5' cy='80.0' r='2.3'/><circle cx='71.0' cy='80.0' r='2.2'/><circle cx='82.5' cy='80.0' r='2.2'/><circle cx='94.0' cy='80.0' r='2.1'/><circle cx='105.5' cy='80.0' r='2.0'/><circle cx='117.0' cy='80.0' r='2.0'/><circle cx='128.5' cy='80.0' r='1.9'/><circle cx='140.0' cy='80.0' r='1.9'/><circle cx='151.5' cy='80.0' r='1.8'/><circle cx='163.0' cy='80.0' r='1.8'/><circle cx='174.5' cy='80.0' r='1.7'/><circle cx='186.0' cy='80.0' r='1.6'/><circle cx='197.5' cy='80.0' r='1.6'/><circle cx='7.8' cy='91.5' r='3.0'/><circle cx='19.2' cy='91.5' r='2.9'/><circle cx='30.8' cy='91.5' r='2.9'/><circle cx='42.2' cy='91.5' r='2.8'/><circle cx='53.8' cy='91.5' r='2.8'/><circle cx='65.2' cy='91.5' r='2.7'/><circle cx='76.8' cy='91.5' r='2.7'/><circle cx='88.2' cy='91.5' r='2.6'/><circle cx='99.8' cy='91.5' r='2.5'/><circle cx='111.2' cy='91.5' r='2.5'/><circle cx='122.8' cy='91.5' r='2.4'/><circle cx='134.2' cy='91.5' r='2.4'/><circle cx='145.8' cy='91.5' r='2.3'/><circle cx='157.2' cy='91.5' r='2.3'/><circle cx='168.8' cy='91.5' r='2.2'/><circle cx='180.2' cy='91.5' r='2.2'/><circle cx='191.8' cy='91.5' r='2.1'/><circle cx='203.2' cy='91.5' r='2.1'/><circle cx='2.0' cy='103.0' r='3.4'/><circle cx='13.5' cy='103.0' r='3.4'/><circle cx='25.0' cy='103.0' r='3.3'/><circle cx='36.5' cy='103.0' r='3.3'/><circle cx='48.0' cy='103.0' r='3.2'/><circle cx='59.5' cy='103.0' r='3.2'/><circle cx='71.0' cy='103.0' r='3.1'/><circle cx='82.5' cy='103.0' r='3.1'/><circle cx='94.0' cy='103.0' r='3.0'/><circle cx='105.5' cy='103.0' r='2.9'/><circle cx='117.0' cy='103.0' r='2.9'/><circle cx='128.5' cy='103.0' r='2.8'/><circle cx='140.0' cy='103.0' r='2.8'/><circle cx='151.5' cy='103.0' r='2.7'/><circle cx='163.0' cy='103.0' r='2.7'/><circle cx='174.5' cy='103.0' r='2.6'/><circle cx='186.0' cy='103.0' r='2.5'/><circle cx='197.5' cy='103.0' r='2.5'/><circle cx='7.8' cy='114.5' r='3.9'/><circle cx='19.2' cy='114.5' r='3.9'/><circle cx='30.8' cy='114.5' r='3.8'/><circle cx='42.2' cy='114.5' r='3.7'/><circle cx='53.8' cy='114.5' r='3.7'/><circle cx='65.2' cy='114.5' r='3.6'/><circle cx='76.8' cy='114.5' r='3.6'/><circle cx='88.2' cy='114.5' r='3.5'/><circle cx='99.8' cy='114.5' r='3.5'/><circle cx='111.2' cy='114.5' r='3.4'/><circle cx='122.8' cy='114.5' r='3.3'/><circle cx='134.2' cy='114.5' r='3.3'/><circle cx='145.8' cy='114.5' r='3.2'/><circle cx='157.2' cy='114.5' r='3.2'/><circle cx='168.8' cy='114.5' r='3.1'/><circle cx='180.2' cy='114.5' r='3.1'/><circle cx='191.8' cy='114.5' r='3.0'/><circle cx='203.2' cy='114.5' r='3.0'/><circle cx='2.0' cy='126.0' r='4.3'/><circle cx='13.5' cy='126.0' r='4.3'/><circle cx='25.0' cy='126.0' r='4.2'/><circle cx='36.5' cy='126.0' r='4.2'/><circle cx='48.0' cy='126.0' r='4.1'/><circle cx='59.5' cy='126.0' r='4.1'/><circle cx='71.0' cy='126.0' r='4.0'/><circle cx='82.5' cy='126.0' r='4.0'/><circle cx='94.0' cy='126.0' r='3.9'/><circle cx='105.5' cy='126.0' r='3.8'/><circle cx='117.0' cy='126.0' r='3.8'/><circle cx='128.5' cy='126.0' r='3.7'/><circle cx='140.0' cy='126.0' r='3.7'/><circle cx='151.5' cy='126.0' r='3.6'/><circle cx='163.0' cy='126.0' r='3.6'/><circle cx='174.5' cy='126.0' r='3.5'/><circle cx='186.0' cy='126.0' r='3.4'/><circle cx='197.5' cy='126.0' r='3.4'/><circle cx='7.8' cy='137.5' r='4.8'/><circle cx='19.2' cy='137.5' r='4.8'/><circle cx='30.8' cy='137.5' r='4.7'/><circle cx='42.2' cy='137.5' r='4.6'/><circle cx='53.8' cy='137.5' r='4.6'/><circle cx='65.2' cy='137.5' r='4.5'/><circle cx='76.8' cy='137.5' r='4.5'/><circle cx='88.2' cy='137.5' r='4.4'/><circle cx='99.8' cy='137.5' r='4.4'/><circle cx='111.2' cy='137.5' r='4.3'/><circle cx='122.8' cy='137.5' r='4.2'/><circle cx='134.2' cy='137.5' r='4.2'/><circle cx='145.8' cy='137.5' r='4.1'/><circle cx='157.2' cy='137.5' r='4.1'/><circle cx='168.8' cy='137.5' r='4.0'/><circle cx='180.2' cy='137.5' r='4.0'/><circle cx='191.8' cy='137.5' r='3.9'/><circle cx='203.2' cy='137.5' r='3.9'/><circle cx='2.0' cy='149.0' r='5.2'/><circle cx='13.5' cy='149.0' r='5.2'/><circle cx='25.0' cy='149.0' r='5.1'/><circle cx='36.5' cy='149.0' r='5.1'/><circle cx='48.0' cy='149.0' r='5.0'/><circle cx='59.5' cy='149.0' r='5.0'/><circle cx='71.0' cy='149.0' r='4.9'/><circle cx='82.5' cy='149.0' r='4.9'/><circle cx='94.0' cy='149.0' r='4.8'/><circle cx='105.5' cy='149.0' r='4.7'/><circle cx='117.0' cy='149.0' r='4.7'/><circle cx='128.5' cy='149.0' r='4.6'/><circle cx='140.0' cy='149.0' r='4.6'/><circle cx='151.5' cy='149.0' r='4.5'/><circle cx='163.0' cy='149.0' r='4.5'/><circle cx='174.5' cy='149.0' r='4.4'/><circle cx='186.0' cy='149.0' r='4.4'/><circle cx='197.5' cy='149.0' r='4.3'/><circle cx='7.8' cy='160.5' r='5.7'/><circle cx='19.2' cy='160.5' r='5.7'/><circle cx='30.8' cy='160.5' r='5.6'/><circle cx='42.2' cy='160.5' r='5.5'/><circle cx='53.8' cy='160.5' r='5.5'/><circle cx='65.2' cy='160.5' r='5.4'/><circle cx='76.8' cy='160.5' r='5.4'/><circle cx='88.2' cy='160.5' r='5.3'/><circle cx='99.8' cy='160.5' r='5.3'/><circle cx='111.2' cy='160.5' r='5.2'/><circle cx='122.8' cy='160.5' r='5.1'/><circle cx='134.2' cy='160.5' r='5.1'/><circle cx='145.8' cy='160.5' r='5.0'/><circle cx='157.2' cy='160.5' r='5.0'/><circle cx='168.8' cy='160.5' r='4.9'/><circle cx='180.2' cy='160.5' r='4.9'/><circle cx='191.8' cy='160.5' r='4.8'/><circle cx='203.2' cy='160.5' r='4.8'/><circle cx='2.0' cy='172.0' r='5.9'/><circle cx='13.5' cy='172.0' r='5.9'/><circle cx='25.0' cy='172.0' r='5.8'/><circle cx='36.5' cy='172.0' r='5.8'/><circle cx='48.0' cy='172.0' r='5.7'/><circle cx='59.5' cy='172.0' r='5.6'/><circle cx='71.0' cy='172.0' r='5.6'/><circle cx='82.5' cy='172.0' r='5.5'/><circle cx='94.0' cy='172.0' r='5.5'/><circle cx='105.5' cy='172.0' r='5.4'/><circle cx='117.0' cy='172.0' r='5.4'/><circle cx='128.5' cy='172.0' r='5.3'/><circle cx='140.0' cy='172.0' r='5.2'/><circle cx='151.5' cy='172.0' r='5.2'/><circle cx='163.0' cy='172.0' r='5.1'/><circle cx='174.5' cy='172.0' r='5.1'/><circle cx='186.0' cy='172.0' r='5.0'/><circle cx='197.5' cy='172.0' r='5.0'/>"

  # stat key => {bright fill, dark rim/dots, default label}
  @stats %{
    thw: {"#27a4dc", "#135882", "THW"},
    atk: {"#e02626", "#7c1111", "ATK"},
    def: {"#49b52b", "#256714", "DEF"},
    sch: {"#6b52c9", "#362466", "SCH"},
    hp: {"#f0a021", "#8a5406", "HP"},
    rec: {"#e0a52b", "#8a5406", "REC"}
  }

  @doc """
  Renders one stat badge.

  ## Examples

      <.stat_badge stat={:atk} value={3} />
      <.stat_badge stat={:thw} value={1} size={64} />
      <.stat_badge stat={:atk} value={2} consequential={2} />
      <.stat_badge stat={:atk} value={2} star />
      <.stat_badge stat={:def} value="*" bright="#49b52b" dark="#256714" label="DEF" />
  """
  attr :stat, :any, default: :thw, doc: "stat key (:thw :atk :def :sch :hp :rec) or custom string"
  attr :value, :any, default: nil, doc: "number/marker shown in the star"
  attr :size, :integer, default: 88, doc: "rendered width in px"
  attr :label, :string, default: nil, doc: "override the plate label"
  attr :bright, :string, default: nil, doc: "override the bright fill color"
  attr :dark, :string, default: nil, doc: "override the dark rim/dot color"
  attr :tilt, :integer, default: @tilt, doc: "star tilt in degrees (plate/text stay flat)"
  attr :hero, :boolean, default: false, doc: "Whether or not this stat is for a hero card"

  attr :consequential, :integer,
    default: 0,
    doc:
      "number of consequential-damage stars shown under the label (0 hides the row and shrinks the plate)"

  attr :star, :boolean,
    default: false,
    doc: "show a small star (ChampionsIcons 's') at the top-right of the number"

  attr :class, :string, default: nil
  attr :rest, :global

  def stat_badge(assigns) do
    stat = to_stat(assigns.stat)

    {b, d, lbl} =
      Map.get(@stats, stat, {"#8a8f98", "#3a3d44", stat |> to_string() |> String.upcase()})

    # Unique per instance so the internal clip/gradient/filter ids never collide,
    # even when the same badge is rendered more than once on a page.
    uid = "sb#{System.unique_integer([:positive])}"

    conseq = max(assigns.consequential || 0, 0)
    # Plate grows a row taller when it carries consequential stars; sides keep the
    # same lean so the short and tall variants read as the same shape.
    plate_bottom = if assigns.hero, do: 224, else: 264
    dy = plate_bottom - 162
    bottom_l = Float.round(16 + -16 / 102 * dy, 1)
    bottom_r = Float.round(196 + -16 / 102 * dy, 1)
    vb_height = plate_bottom + 18

    assigns =
      assign(assigns,
        bright: assigns.bright || b,
        dark: assigns.dark || d,
        label: assigns.label || lbl,
        uid: uid,
        conseq: conseq,
        stars: String.duplicate("d", conseq),
        vb_height: vb_height,
        height: round(assigns.size * vb_height / 260),
        plate: "M 16 162 L 196 162 L #{bottom_r} #{plate_bottom} L #{bottom_l} #{plate_bottom} Z",
        burst: @burst,
        dots: @dots
      )

    ~H"""
    <svg
      class={@class}
      width={@size}
      height={@height}
      viewBox={"-30 0 260 #{@vb_height}"}
      role="img"
      aria-label={"#{@label} #{@value}"}
      style="overflow:visible"
      {@rest}
    >
      <defs>
        <clipPath id={"clip-#{@uid}"}>
          <path d={@burst} />
        </clipPath>
        <radialGradient id={"fill-#{@uid}"} gradientUnits="userSpaceOnUse" cx="100" cy="84.7" r="101">
          <stop offset="0%" stop-color={@bright} />
          <stop offset="52%" stop-color={@bright} />
          <stop offset="100%" stop-color={@dark} />
        </radialGradient>
        <filter id={"shadow-#{@uid}"} x="-30%" y="-30%" width="160%" height="170%">
          <feDropShadow dx="-2.5" dy="4" stdDeviation="1.2" flood-color="#000" flood-opacity="0.55" />
        </filter>
      </defs>

      <g transform={"rotate(#{@tilt} 100 110)"}>
        <path
          d={@burst}
          fill="none"
          stroke="#fbfbfb"
          stroke-width="20"
          stroke-linejoin="miter"
          stroke-miterlimit="9"
        />
        <path
          d={@burst}
          fill={"url(#fill-#{@uid})"}
          stroke="#141418"
          stroke-width="4"
          stroke-linejoin="miter"
          stroke-miterlimit="9"
        />
        <g clip-path={"url(#clip-#{@uid})"} fill={@dark} opacity="0.82">{Phoenix.HTML.raw(@dots)}</g>
      </g>

      <path d={@plate} fill="#141418" stroke="#fbfbfb" stroke-width="4" stroke-linejoin="round" />
      <text
        x={if @star, do: "104", else: "100"}
        y="111"
        text-anchor="middle"
        dominant-baseline="central"
        fill="#fff"
        stroke="#101014"
        stroke-width="7.2"
        stroke-linejoin="round"
        style="font-family:'ElektraMed','Elektra Medium Pro',sans-serif;font-weight:700;font-style:italic;font-size:120px;paint-order:stroke"
        filter={"url(#shadow-#{@uid})"}
      >
        {@value}
        <tspan
          :if={@star}
          dx="1"
          dy="-34"
          stroke-width="3"
          style="font-family:'ChampionsIcons';font-style:normal;font-size:42px;paint-order:stroke"
        >
          s
        </tspan>
      </text>
      <text
        x="100"
        y={if @conseq > 0, do: "189", else: "188"}
        text-anchor="middle"
        dominant-baseline="central"
        fill="#fff"
        style="font-family:'Exo2',sans-serif;font-weight:900;font-size:44px;letter-spacing:1px"
      >
        {@label}
      </text>
      <text
        :if={@conseq > 0}
        x="100"
        y="234"
        text-anchor="middle"
        dominant-baseline="central"
        fill="#fff"
        style="font-family:'ChampionsIcons';font-size:40px;letter-spacing:4px"
      >
        {@stars}
      </text>
    </svg>
    """
  end

  defp to_stat(s) when is_atom(s), do: s

  # Map known strings to their atom key without creating atoms from arbitrary
  # input; unknown strings fall through to the default palette in stat_badge/1.
  defp to_stat(s) when is_binary(s) do
    case String.downcase(s) do
      "thw" -> :thw
      "atk" -> :atk
      "def" -> :def
      "sch" -> :sch
      "hp" -> :hp
      "rec" -> :rec
      other -> other
    end
  end
end
