defmodule SanctumWeb.Components.ChampionsIcons do
  @moduledoc """
  Function components for the ChampionsIcons glyph font — one component per
  icon, so call sites never hard-code `font-champions` spans or raw glyph
  letters.

  Each component renders an inline `<span>` with the right glyph and (for the
  four resources) its `text-res-*` color. Icons size with `font-size`, so pass
  a text-size class: `<.energy_icon class="text-2xl" />`. `normal-case` is
  baked in because the glyph letters are case-sensitive — an inherited
  `uppercase` would swap them for different icons.

  For dynamic icon lists (resource pips, the icon picker) use the
  `champions_icon` dispatcher with a token from `Sanctum.CardText.icons/0`,
  which remains the single source of truth for the token → glyph map. The two
  glyphs with no card-text token — the per-player marker and the stat star —
  live here under the `"player"` and `"stat_star"` tokens.

  Not covered here: the SVG badges (`StatBadge`, `HealthBadge`) draw their
  glyphs as `<tspan>`s inside SVG `<text>`, where an HTML span can't go.
  """
  use Phoenix.Component

  # Card-text tokens (from CardText, the source of truth) plus the two
  # glyphs that only appear outside card text: the per-player marker ("v",
  # threat plates / health badges) and the stat-effect star ("s", stat badges).
  @glyphs Map.merge(Sanctum.CardText.icons(), %{
            "player" => {"v", nil},
            "stat_star" => {"s", nil}
          })

  @resources ~w(energy mental physical wild)

  @doc """
  Renders the icon for a ChampionsIcons token — for call sites that pick the
  icon at runtime (resource pips, the icon picker). Unknown tokens render
  nothing, mirroring `resource_pips/1` dropping unknown resources.

  ## Examples

      <.champions_icon token="energy" class="text-2xl" />
      <.champions_icon :for={token <- @side.pips} token={token} class="text-sm" />
  """
  attr :token, :any, required: true, doc: "token atom/string from Sanctum.CardText.icons/0"
  attr :class, :any, default: nil
  attr :rest, :global

  def champions_icon(assigns) do
    case Map.get(@glyphs, to_string(assigns.token)) do
      {glyph, color} ->
        assigns = assign(assigns, glyph: glyph, color: color)

        ~H"""
        <span class={["font-champions normal-case leading-none", @color, @class]} {@rest}>
          {@glyph}
        </span>
        """

      nil ->
        ~H""
    end
  end

  @doc "The energy resource icon (`[energy]`)."
  attr :class, :any, default: nil
  attr :rest, :global
  def energy_icon(assigns), do: icon(assigns, "energy")

  @doc "The mental resource icon (`[mental]`)."
  attr :class, :any, default: nil
  attr :rest, :global
  def mental_icon(assigns), do: icon(assigns, "mental")

  @doc "The physical resource icon (`[physical]`)."
  attr :class, :any, default: nil
  attr :rest, :global
  def physical_icon(assigns), do: icon(assigns, "physical")

  @doc "The wild resource icon (`[wild]`)."
  attr :class, :any, default: nil
  attr :rest, :global
  def wild_icon(assigns), do: icon(assigns, "wild")

  @doc "The resource-cost icon (`[cost]`)."
  attr :class, :any, default: nil
  attr :rest, :global
  def cost_icon(assigns), do: icon(assigns, "cost")

  @doc "The card-text star icon (`[star]`)."
  attr :class, :any, default: nil
  attr :rest, :global
  def star_icon(assigns), do: icon(assigns, "star")

  @doc "The boost icon (`[boost]`)."
  attr :class, :any, default: nil
  attr :rest, :global
  def boost_icon(assigns), do: icon(assigns, "boost")

  @doc "The crisis icon (`[crisis]`)."
  attr :class, :any, default: nil
  attr :rest, :global
  def crisis_icon(assigns), do: icon(assigns, "crisis")

  @doc "The hazard icon (`[hazard]`)."
  attr :class, :any, default: nil
  attr :rest, :global
  def hazard_icon(assigns), do: icon(assigns, "hazard")

  @doc "The acceleration icon (`[acceleration]`)."
  attr :class, :any, default: nil
  attr :rest, :global
  def acceleration_icon(assigns), do: icon(assigns, "acceleration")

  @doc "The amplify icon (`[amplify]`)."
  attr :class, :any, default: nil
  attr :rest, :global
  def amplify_icon(assigns), do: icon(assigns, "amplify")

  @doc "The per-hero icon (`[per_hero]`)."
  attr :class, :any, default: nil
  attr :rest, :global
  def per_hero_icon(assigns), do: icon(assigns, "per_hero")

  @doc "The per-group icon (`[per_group]`)."
  attr :class, :any, default: nil
  attr :rest, :global
  def per_group_icon(assigns), do: icon(assigns, "per_group")

  @doc "The uniqueness icon (`[unique]`)."
  attr :class, :any, default: nil
  attr :rest, :global
  def unique_icon(assigns), do: icon(assigns, "unique")

  @doc "The per-player marker — scheme threat plates, health badges."
  attr :class, :any, default: nil
  attr :rest, :global
  def player_icon(assigns), do: icon(assigns, "player")

  @doc "The stat-effect star — marks a stat with an associated special effect."
  attr :class, :any, default: nil
  attr :rest, :global
  def stat_star_icon(assigns), do: icon(assigns, "stat_star")

  defp icon(assigns, token) do
    {glyph, color} = Map.fetch!(@glyphs, token)
    assigns = assign(assigns, glyph: glyph, color: color)

    ~H"""
    <span class={["font-champions normal-case leading-none", @color, @class]} {@rest}>
      {@glyph}
    </span>
    """
  end

  @doc """
  Normalizes a list of resource atoms/strings into pip tokens for
  `champions_icon/1` — one entry per pip, unknown resources dropped.
  """
  def resource_pips(resources) do
    resources |> Enum.map(&to_string/1) |> Enum.filter(&(&1 in @resources))
  end
end
