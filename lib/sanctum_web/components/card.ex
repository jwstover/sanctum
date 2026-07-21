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

  # Tailwind color-class trio per aspect (backed by the --color-aspect-*
  # tokens in app.css). Full literal class names so Tailwind's source
  # scanner detects them; do not build these by interpolation.
  @aspect_classes %{
    "hero" => %{text: "text-aspect-hero", bg: "bg-aspect-hero", border: "border-aspect-hero"},
    "aggression" => %{
      text: "text-aspect-aggression",
      bg: "bg-aspect-aggression",
      border: "border-aspect-aggression"
    },
    "justice" => %{
      text: "text-aspect-justice",
      bg: "bg-aspect-justice",
      border: "border-aspect-justice"
    },
    "leadership" => %{
      text: "text-aspect-leadership",
      bg: "bg-aspect-leadership",
      border: "border-aspect-leadership"
    },
    "protection" => %{
      text: "text-aspect-protection",
      bg: "bg-aspect-protection",
      border: "border-aspect-protection"
    },
    "pool" => %{text: "text-aspect-pool", bg: "bg-aspect-pool", border: "border-aspect-pool"},
    "basic" => %{text: "text-aspect-basic", bg: "bg-aspect-basic", border: "border-aspect-basic"},
    "encounter" => %{
      text: "text-aspect-encounter",
      bg: "bg-aspect-encounter",
      border: "border-aspect-encounter"
    }
  }

  @res %{
    "energy" => {"text-res-energy", "E"},
    "mental" => {"text-res-mental", "M"},
    "physical" => {"text-res-physical", "P"},
    "wild" => {"text-res-wild", "W"}
  }

  @dims %{
    "sm" => %{pad: 6, title: 11, sub: 8, cost: 17, res: 13, label: 7, badge: 18},
    "md" => %{pad: 9, title: 14, sub: 10, cost: 25, res: 18, label: 9, badge: 21},
    "lg" => %{pad: 13, title: 20, sub: 13, cost: 34, res: 24, label: 11, badge: 26}
  }

  # Card types printed in landscape orientation (wider than tall): schemes.
  # Villains, identities, and environments are portrait. Consumers use this to
  # pick a landscape frame instead of the default portrait one.
  @landscape_types [:main_scheme, :side_scheme, :player_side_scheme]

  @doc "Whether a card type is printed in landscape orientation."
  def landscape_type?(type), do: type in @landscape_types

  @doc """
  Display form of a printed card value: MarvelCDB encodes a printed X
  (X cost, X attack, X threat, …) as `-1` — map it back to `"X"`.
  """
  def display_value(-1), do: "X"
  def display_value(value), do: value

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
    aspect_classes = aspect_classes(aspect)
    dims = Map.get(@dims, assigns.size, @dims["md"])

    pips =
      assigns.resources
      |> Enum.map(&to_s/1)
      |> Enum.map(&Map.get(@res, &1))
      |> Enum.reject(&is_nil/1)

    has_cost? = assigns.show_cost and assigns.cost not in [nil, ""] and type != "resource"

    # Hero cards get a MarvelCDB gradient border painted via border-box, so
    # that background stays inline (dynamic colors). Other aspects use the
    # solid `bg-base-200` utility and a `border-aspect-*` class instead.
    card_style =
      if hero? do
        {default_from, default_to} = @default_gradient
        from = assigns.gradient_from || default_from
        to = assigns.gradient_to || default_to

        "background:linear-gradient(var(--color-base-200),var(--color-base-200)) padding-box," <>
          "linear-gradient(135deg,#{from},#{to}) border-box;"
      else
        ""
      end

    assigns =
      assign(assigns,
        cost: display_value(assigns.cost),
        aspect_classes: aspect_classes,
        hero?: hero?,
        dims: dims,
        pips: pips,
        has_cost?: has_cost?,
        card_style: card_style,
        border_class: if(hero?, do: "border-transparent", else: aspect_classes.border),
        type_label: type_label(type),
        show_res?: assigns.size != "sm" and pips != [] and assigns.qty == 0,
        show_qty?: assigns.qty > 0,
        has_img?: assigns.image_url not in [nil, ""]
      )

    ~H"""
    <div
      class={[
        "relative h-full w-full overflow-hidden rounded-[7px] border-2 font-barlow-condensed text-white",
        @border_class,
        !@hero? && "bg-base-200",
        @class
      ]}
      style={"#{@card_style}box-shadow:0 4px 14px rgba(0,0,0,.5);"}
      {@rest}
    >
      <!-- diagonal-hatch art placeholder -->
      <div class="bg-card-hatch absolute inset-0"></div>
      <div class="absolute inset-x-0 top-[38%] flex items-center justify-center">
        <span
          class="font-ibm-mono uppercase tracking-[0.2em] text-white/[0.32]"
          style={"font-size:#{@dims.label}px;"}
        >
          card&nbsp;art
        </span>
      </div>

      <!-- aspect stripe -->
      <div class={["absolute inset-y-0 left-0 w-[5px]", @aspect_classes.bg]}></div>

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
        class={[
          "font-elektra absolute left-[9px] top-[6px] z-[3] flex items-center justify-center rounded-full border-2 bg-base-100",
          @aspect_classes.border
        ]}
        style={"width:#{@dims.cost}px;height:#{@dims.cost}px;font-size:#{@dims.sub}px;box-shadow:0 2px 5px rgba(0,0,0,.5);"}
      >
        {@cost}
      </div>

      <!-- resource pips -->
      <div :if={@show_res?} class="absolute right-[6px] top-[6px] z-[3] flex gap-[3px]">
        <span
          :for={{color_class, glyph} <- @pips}
          class={["font-champions leading-none", color_class]}
          style={"font-size:#{@dims.res}px;text-shadow:0 1px 2px rgba(0,0,0,.95),0 0 3px rgba(0,0,0,.8);"}
        >
          {glyph}
        </span>
      </div>

      <!-- quantity badge -->
      <div
        :if={@show_qty?}
        class="absolute right-[6px] top-[6px] z-[3] flex items-center justify-center rounded-[5px] bg-white font-anton text-base-100"
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
          <span class={["size-[7px] rounded-[1px]", @aspect_classes.bg]}></span>
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
  Maps a list of resource atoms/strings to `{text_color_class, glyph}` tuples
  for rendering ChampionsIcons pips outside a card face (e.g. a detail row).
  The class (e.g. `"text-res-energy"`) goes on the element's `class`, not an
  inline style. Unknown resources are dropped.
  """
  def resource_pips(resources) do
    resources
    |> Enum.map(&to_s/1)
    |> Enum.map(&Map.get(@res, &1))
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Tailwind color classes for an aspect as `%{text:, bg:, border:}` (backed by
  the `--color-aspect-*` theme tokens). Unknown aspects fall back to `basic`.
  Use these classes instead of inline color styles so the prod CSP can keep
  `style-src` free of inline color rules.
  """
  def aspect_classes(aspect) do
    Map.get(@aspect_classes, to_s(aspect), @aspect_classes["basic"])
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
