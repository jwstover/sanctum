defmodule SanctumWeb.Components.Card do
  @moduledoc """
  The `MCCard` mini-card — a port of the design system's `MCCard.dc.html`.

  Renders a Marvel Champions card face: aspect-colored stripe, cost bubble,
  resource pips (ChampionsIcons glyphs), quantity badge, and a bottom title
  gradient. Hero cards get the Spider-Man red→blue gradient border; every
  other aspect keeps its solid aspect color.

  The card art itself has rounded corners and a soft shadow — the signature
  hard black border + offset shadow belongs to the *tile wrapper* around it
  (see `SanctumWeb.CoreComponents.panel/1`), not the card.
  """
  use Phoenix.Component

  @aspect %{
    "hero" => "#ce1b2e",
    "aggression" => "#b12020",
    "justice" => "#dbcb36",
    "leadership" => "#2ea7b8",
    "protection" => "#46991b",
    "pool" => "#d074ac",
    "basic" => "#87868f"
  }

  @res %{
    "energy" => {"var(--res-energy)", "E"},
    "mental" => {"var(--res-mental)", "M"},
    "physical" => {"var(--res-physical)", "P"},
    "wild" => {"var(--res-wild)", "W"}
  }

  @dims %{
    "sm" => %{pad: 6, title: 11, sub: 8, cost: 17, res: 13, label: 7, badge: 18},
    "md" => %{pad: 9, title: 14, sub: 10, cost: 25, res: 18, label: 9, badge: 21},
    "lg" => %{pad: 13, title: 20, sub: 13, cost: 34, res: 24, label: 11, badge: 26}
  }

  # Fallback gradient when a hero has no stored palette (non-hero sets,
  # un-synced heroes). Hero colors themselves come from MarvelCDB and are
  # passed in via gradient_from/gradient_to.
  @default_gradient {"#ce1b2e", "#234fa6"}

  @doc """
  Renders a card face.

  ## Examples

      <.mc_card name="Web-Shooter" cost={1} type="upgrade" aspect="hero"
        resources={[:mental]} image_url={@side.image_url} size="md" />
  """
  attr :name, :string, default: "Card"
  attr :cost, :any, default: nil
  attr :type, :any, default: "event"
  attr :aspect, :any, default: "hero"
  attr :resources, :list, default: [], doc: "list of resource atoms/strings, one per pip"
  attr :qty, :integer, default: 0
  attr :size, :string, default: "md", values: ~w(sm md lg)
  attr :image_url, :string, default: nil

  attr :gradient_from, :string,
    default: nil,
    doc: "hero gradient-border start color; falls back to the default when nil"

  attr :gradient_to, :string, default: nil, doc: "hero gradient-border end color"
  attr :show_cost, :boolean, default: true, doc: "render the cost bubble overlay"
  attr :class, :string, default: ""
  attr :rest, :global

  def mc_card(assigns) do
    aspect = to_s(assigns.aspect)
    type = to_s(assigns.type)
    hero? = aspect == "hero"
    aspect_color = Map.get(@aspect, aspect, @aspect["basic"])
    dims = Map.get(@dims, assigns.size, @dims["md"])

    pips =
      assigns.resources
      |> Enum.map(&to_s/1)
      |> Enum.map(&Map.get(@res, &1))
      |> Enum.reject(&is_nil/1)

    has_cost? = assigns.show_cost and assigns.cost not in [nil, ""] and type != "resource"

    card_bg =
      if hero? do
        {default_from, default_to} = @default_gradient
        from = assigns.gradient_from || default_from
        to = assigns.gradient_to || default_to

        "linear-gradient(#15151a,#15151a) padding-box, " <>
          "linear-gradient(135deg, #{from}, #{to}) border-box"
      else
        "#15151a"
      end

    assigns =
      assign(assigns,
        aspect_color: aspect_color,
        dims: dims,
        pips: pips,
        has_cost?: has_cost?,
        card_bg: card_bg,
        border_color: if(hero?, do: "transparent", else: aspect_color),
        type_label: type_label(type),
        show_res?: assigns.size != "sm" and pips != [] and assigns.qty == 0,
        show_qty?: assigns.qty > 0,
        has_img?: assigns.image_url not in [nil, ""]
      )

    ~H"""
    <div
      class={[
        "relative h-full w-full overflow-hidden rounded-[7px] font-barlow-condensed text-white",
        @class
      ]}
      style={"background:#{@card_bg};border:2px solid #{@border_color};box-shadow:0 4px 14px rgba(0,0,0,.5);"}
      {@rest}
    >
      <!-- diagonal-hatch art placeholder -->
      <div
        class="absolute inset-0"
        style="background:repeating-linear-gradient(135deg,#1b1b21 0 7px,#23232c 7px 14px);"
      >
      </div>
      <div class="absolute inset-x-0 top-[38%] flex items-center justify-center">
        <span
          class="font-ibm-mono uppercase tracking-[0.2em]"
          style={"font-size:#{@dims.label}px;color:rgba(255,255,255,.32);"}
        >
          card&nbsp;art
        </span>
      </div>

      <!-- aspect stripe -->
      <div class="absolute inset-y-0 left-0 w-[5px]" style={"background:#{@aspect_color};"}></div>

      <!-- card image -->
      <img
        :if={@has_img?}
        src={@image_url}
        alt={@name}
        class="absolute inset-0 z-[2] block h-full w-full object-cover"
      />

      <!-- cost bubble -->
      <div
        :if={@has_cost?}
        class="absolute left-[9px] top-[6px] z-[3] flex items-center justify-center rounded-full font-anton"
        style={"width:#{@dims.cost}px;height:#{@dims.cost}px;background:#0c0c0f;border:2px solid #{@aspect_color};font-size:#{@dims.sub}px;box-shadow:0 2px 5px rgba(0,0,0,.5);"}
      >
        {@cost}
      </div>

      <!-- resource pips -->
      <div :if={@show_res?} class="absolute right-[6px] top-[6px] z-[3] flex gap-[3px]">
        <span
          :for={{color, glyph} <- @pips}
          class="font-champions leading-none"
          style={"font-size:#{@dims.res}px;color:#{color};text-shadow:0 1px 2px rgba(0,0,0,.95),0 0 3px rgba(0,0,0,.8);"}
        >
          {glyph}
        </span>
      </div>

      <!-- quantity badge -->
      <div
        :if={@show_qty?}
        class="absolute right-[6px] top-[6px] z-[3] flex items-center justify-center rounded-[5px] bg-white font-anton text-[#0c0c0f]"
        style={"min-width:#{@dims.badge}px;height:#{@dims.badge}px;padding:0 5px;font-size:#{@dims.sub}px;box-shadow:0 2px 6px rgba(0,0,0,.6);"}
      >
        ×{@qty}
      </div>

      <!-- bottom title gradient -->
      <div
        class="absolute inset-x-0 bottom-0 z-[3]"
        style={"padding:#{@dims.pad}px;background:linear-gradient(to top,rgba(7,7,9,.97) 0%,rgba(7,7,9,.78) 55%,transparent 100%);"}
      >
        <div
          class="font-bold uppercase leading-[1.02] tracking-[0.005em] [text-wrap:balance]"
          style={"font-size:#{@dims.title}px;"}
        >
          {@name}
        </div>
        <div class="mt-1 flex items-center gap-[5px]">
          <span class="rounded-[1px]" style={"width:7px;height:7px;background:#{@aspect_color};"}></span>
          <span
            class="font-semibold uppercase tracking-[0.16em] text-white/60"
            style={"font-size:#{@dims.label}px;"}
          >
            {@type_label}
          </span>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Maps a list of resource atoms/strings to `{css_color, glyph}` tuples for
  rendering ChampionsIcons pips outside a card face (e.g. a detail row).
  Unknown resources are dropped.
  """
  def resource_pips(resources) do
    resources
    |> Enum.map(&to_s/1)
    |> Enum.map(&Map.get(@res, &1))
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  A stable `{from, to}` gradient derived from a set slug, for heroes with no
  stored MarvelCDB palette (or non-hero sets). Deterministic per slug.
  """
  def fallback_gradient(slug) when slug in [nil, ""], do: @default_gradient

  def fallback_gradient(slug) do
    h = :erlang.phash2(to_s(slug), 360)
    {"hsl(#{h} 60% 46%)", "hsl(#{rem(h + 40, 360)} 55% 38%)"}
  end

  defp to_s(nil), do: ""
  defp to_s(v) when is_atom(v), do: Atom.to_string(v)
  defp to_s(v), do: to_string(v)

  defp type_label(type) do
    type |> String.replace("_", "-") |> String.upcase()
  end
end
