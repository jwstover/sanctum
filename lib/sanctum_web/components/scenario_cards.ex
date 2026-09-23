defmodule SanctumWeb.Components.ScenarioCards do
  @moduledoc """
  Shared presentation helpers for scenarios: the villain art shown on a
  scenario's cover, the author (owner, or "Official") shown beside it, each
  encounter set's card fan, and the combined content-stats panel covering the
  whole encounter deck.
  """

  use Phoenix.Component

  import SanctumWeb.Components.Card, only: [mc_card: 1]
  import SanctumWeb.Components.ChampionsIcons, only: [champions_icon: 1]

  # Card types counted in an encounter set's stats tiles, in display order.
  # Villain/main-scheme cards are structural (one-of, not "content") and are
  # left out on purpose.
  @count_types [
    {:minion, "Minions"},
    {:treachery, "Treacheries"},
    {:side_scheme, "Side Schemes"},
    {:attachment, "Attachments"},
    {:upgrade, "Upgrades"},
    {:support, "Support"},
    {:obligation, "Obligations"},
    {:environment, "Environment"}
  ]

  @boost_icon_types [:acceleration_icon, :amplify_icon, :crisis_icon, :hazard_icon]

  @doc """
  Computed display data for an encounter set (a scenario's villain set or one
  of its modular sets): a representative "fan" of primary-side cards for that
  set's section. Expects `cards: [:primary_side]` loaded on the
  `Sanctum.Catalog.CardSet`. Returns `nil` for a nil set. Content stats are
  computed separately, combined across every set — see `combined_stats/1`.

  ## Fan selection

  Cards are sorted by `code` (their print order within the set), then reduced
  to one card per distinct type, keeping the earliest — so the fan shows a
  variety of what's in the set, preferring cards printed first.
  """
  def encounter_set_view(nil), do: nil

  def encounter_set_view(%{cards: cards} = card_set) when is_list(cards) do
    %{
      name: card_set.name || card_set.code,
      code: card_set.code,
      fan: fan_cards(to_sides(cards))
    }
  end

  @doc """
  Combined content stats across several encounter sets — the scenario's whole
  encounter deck (villain set + every modular set) — for a single page-level
  stats panel. Expects `cards: [:primary_side]` loaded on each set; `nil`
  entries (an unset villain set) are dropped.
  """
  def combined_stats(card_sets) do
    card_sets
    |> Enum.filter(& &1)
    |> Enum.flat_map(& &1.cards)
    |> to_sides()
    |> content_stats()
  end

  defp to_sides(cards) do
    cards
    |> Enum.sort_by(& &1.code)
    |> Enum.map(&{&1, &1.primary_side})
    |> Enum.reject(fn {_card, side} -> is_nil(side) end)
  end

  defp fan_cards(sides) do
    sides
    |> Enum.uniq_by(fn {_card, side} -> side.type end)
    |> Enum.take(3)
    |> Enum.map(fn {_card, side} ->
      %{name: side.name, type: side.type, image_url: side.image_url}
    end)
  end

  defp content_stats(sides) do
    weight = fn {card, _side} -> card.deck_limit || 1 end
    sum_weight = fn list -> list |> Enum.map(weight) |> Enum.sum() end

    type_counts =
      for {type, _label} <- @count_types,
          group = Enum.filter(sides, fn {_card, side} -> side.type == type end),
          group != [],
          into: %{},
          do: {type, sum_weight.(group)}

    boostable = Enum.filter(sides, fn {_card, side} -> side.boost != nil or side.boost_star end)
    {starred, numeric} = Enum.split_with(boostable, fn {_card, side} -> side.boost_star end)

    boost_curve =
      numeric
      |> Enum.group_by(fn {_card, side} -> side.boost end)
      |> Map.new(fn {boost, group} -> {boost, sum_weight.(group)} end)
      |> Enum.sort()

    numeric_weight = sum_weight.(numeric)

    avg_boost =
      if numeric_weight > 0 do
        total =
          numeric
          |> Enum.map(fn {card, side} -> side.boost * weight.({card, side}) end)
          |> Enum.sum()

        Float.round(total / numeric_weight, 1)
      end

    icon_counts =
      for icon <- @boost_icon_types,
          group = Enum.filter(sides, fn {_card, side} -> Map.get(side, icon) end),
          group != [],
          into: %{},
          do: {icon, sum_weight.(group)}

    %{
      type_counts: type_counts,
      boost_curve: boost_curve,
      boost_star_count: sum_weight.(starred),
      avg_boost: avg_boost,
      icon_counts: icon_counts
    }
  end

  @doc "Whether `stats` (from `combined_stats/1`) has anything worth rendering."
  def stats_present?(stats),
    do: stats.type_counts != %{} or stats.boost_curve != [] or stats.icon_counts != %{}

  @doc """
  Renders an encounter set's content stats: deck-weighted type-count tiles, a
  boost-value bar curve (with average and ★-boost count), and boost-icon
  counts. Renders nothing for a set with no countable content.
  """
  attr :stats, :map, required: true
  attr :class, :string, default: nil

  def encounter_stats(assigns) do
    type_tiles =
      for {type, label} <- @count_types, count = assigns.stats.type_counts[type], count do
        {label, count}
      end

    assigns = assign(assigns, type_tiles: type_tiles)

    ~H"""
    <div
      :if={@type_tiles != [] or @stats.boost_curve != [] or @stats.icon_counts != %{}}
      class={["space-y-3", @class]}
    >
      <div :if={@type_tiles != []} class="grid grid-cols-3 gap-x-3 gap-y-2 sm:grid-cols-4">
        <div :for={{label, count} <- @type_tiles} class="min-w-0">
          <div class="font-anton text-xl leading-none text-secondary">{count}</div>
          <div class="mt-0.5 truncate font-barlow-condensed text-[11px] font-bold uppercase tracking-[0.08em] text-base-content/50">
            {label}
          </div>
        </div>
      </div>

      <div
        :if={@stats.boost_curve != [] or @stats.boost_star_count > 0}
        class="border-t border-line/60 pt-3"
      >
        <div class="flex items-center justify-between">
          <span class="font-ibm-mono text-[11px] uppercase tracking-[0.16em] text-base-content/50">
            Boost curve
          </span>
          <span
            :if={@stats.avg_boost}
            class="font-barlow-condensed text-xs font-bold text-base-content/70"
          >
            avg {@stats.avg_boost}
          </span>
        </div>
        <div class="mt-2 flex h-[44px] items-end gap-1.5">
          <div
            :for={{value, count} <- @stats.boost_curve}
            class="flex h-full flex-1 flex-col justify-end gap-1"
          >
            <div class="w-full bg-primary/70" style={"height:#{bar_height(count, @stats)}px;"}></div>
            <span class="text-center font-ibm-mono text-[10px] text-base-content/50">{value}</span>
          </div>
          <div :if={@stats.boost_star_count > 0} class="flex h-full flex-1 flex-col justify-end gap-1">
            <div
              class="w-full bg-primary/40"
              style={"height:#{bar_height(@stats.boost_star_count, @stats)}px;"}
            >
            </div>
            <span class="text-center font-ibm-mono text-[10px] text-base-content/50">★</span>
          </div>
        </div>
      </div>

      <div :if={@stats.icon_counts != %{}} class="flex flex-wrap gap-3 border-t border-line/60 pt-3">
        <div :for={{icon, count} <- @stats.icon_counts} class="flex items-center gap-1.5">
          <.champions_icon token={icon_token(icon)} class="text-sm text-base-content/70" />
          <span class="font-barlow-condensed text-xs font-bold text-base-content/70">×{count}</span>
        </div>
      </div>
    </div>
    """
  end

  defp icon_token(icon), do: icon |> Atom.to_string() |> String.replace_suffix("_icon", "")

  defp bar_height(count, stats) do
    max =
      [stats.boost_star_count | Enum.map(stats.boost_curve, &elem(&1, 1))]
      |> Enum.max(fn -> 1 end)
      |> max(1)

    max(round(count / max * 36), 4)
  end

  @doc """
  Renders a set's card fan: up to 3 cards, the first centered and on top as
  the highlight, the rest peeking out rotated behind it.
  """
  attr :cards, :list, default: [], doc: "each %{name:, type:, image_url:}, highlight first"
  attr :class, :string, default: nil

  def card_fan(assigns) do
    {highlight, rest} =
      case assigns.cards do
        [] -> {nil, []}
        [h | t] -> {h, t}
      end

    side_styles = [
      "top:22px;left:-16px;right:auto;transform:rotate(-13deg);",
      "top:22px;right:-16px;left:auto;transform:rotate(13deg);"
    ]

    assigns = assign(assigns, highlight: highlight, side_cards: Enum.zip(rest, side_styles))

    ~H"""
    <div class={["relative h-[266px] w-[190px]", @class]}>
      <div
        :for={{c, style} <- @side_cards}
        class="absolute h-[210px] w-[150px] origin-bottom opacity-60 saturate-75"
        style={style}
      >
        <.mc_card
          name={c.name}
          type={c.type}
          aspect="encounter"
          image_url={c.image_url}
          size="md"
          show_cost={false}
        />
      </div>
      <div :if={@highlight} class="absolute inset-0 shadow-comic-sm">
        <.mc_card
          name={@highlight.name}
          type={@highlight.type}
          aspect="encounter"
          image_url={@highlight.image_url}
          size="lg"
          show_cost={false}
        />
      </div>
    </div>
    """
  end

  @doc """
  Primary-stage villain art for a scenario, or nil. Expects `villains:
  [:primary_side]` loaded; the lowest stage wins, ties broken by card code.
  """
  def villain_image(scenario) do
    scenario
    |> sorted_villains()
    |> Enum.find_value(fn %{primary_side: side} ->
      if is_binary(side.image_url), do: side.image_url
    end)
  end

  @doc "The scenario's lowest-stage villain card (with `primary_side` loaded), or nil."
  def primary_villain(scenario), do: scenario |> sorted_villains() |> List.first()

  @doc """
  The villain's name for display: the primary villain side's name, else the
  villain set's name when loaded, else nil.
  """
  def villain_name(scenario) do
    case primary_villain(scenario) do
      %{primary_side: %{name: name}} when is_binary(name) -> name
      _ -> villain_set_name(scenario)
    end
  end

  defp villain_set_name(%{villain_set: %{name: name}}) when is_binary(name), do: name
  defp villain_set_name(_), do: nil

  defp sorted_villains(%{villains: vs}) when is_list(vs) do
    vs
    |> Enum.filter(& &1.primary_side)
    |> Enum.sort_by(&{&1.primary_side.stage || 999, &1.code})
  end

  defp sorted_villains(_), do: []

  @doc """
  The scenario's author as `%{official?, name, avatar}`, or nil when the owner
  isn't loaded / has no username. Matches `owner_id` first so an unloaded owner
  is never read as official.
  """
  def author(%{owner_id: nil}), do: %{official?: true, name: "Official", avatar: nil}

  def author(%{owner: %{username: %Ash.CiString{} = u, avatar_url: avatar}}),
    do: %{official?: false, name: "@" <> to_string(u), avatar: avatar}

  def author(_), do: nil

  @doc "The 'Official' badge shown in place of an author."
  def official_badge(assigns) do
    ~H"""
    <span class="border-2 border-primary bg-black px-2 py-0.5 font-barlow-condensed text-xs font-bold uppercase tracking-[0.08em] text-primary">
      Official
    </span>
    """
  end
end
