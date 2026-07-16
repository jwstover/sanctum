defmodule SanctumWeb.BrowseLive.Show do
  @moduledoc """
  A single product's contents, grouped by card-set role: villains, main scheme,
  modular sets, encounter sets, heroes (each paired with its nemesis set), and a
  Player Cards bucket for the aspect/basic cards that ship in the product but
  belong to no card set.
  """
  use SanctumWeb, :live_view

  require Ash.Query

  alias Sanctum.Catalog
  alias SanctumWeb.Components.Card, as: CardComponent

  @aspect_order %{
    hero: 0,
    aggression: 1,
    justice: 2,
    leadership: 3,
    protection: 4,
    pool: 5,
    basic: 6,
    encounter: 7
  }

  @impl true
  def mount(%{"pack" => code}, _session, socket) do
    case Catalog.get_pack_by_code(code,
           load: [:wave, :card_total, card_sets: [cards: [:primary_side, :card_sides]]]
         ) do
      {:ok, %Catalog.Pack{} = pack} ->
        hero_colors = Sanctum.Heroes.hero_color_map()

        {:ok,
         socket
         |> assign(:page_title, pack.name || pack.code)
         |> assign(:pack, pack)
         |> assign(:villain_groups, villain_groups(pack, hero_colors))
         |> assign(:encounter_groups, encounter_groups(pack, hero_colors))
         |> assign(:sections, build_sections(pack, hero_colors))
         |> assign(:modular_groups, modular_groups(pack, hero_colors))
         |> assign(:player_groups, player_card_groups(pack, hero_colors))}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Unknown product “#{code}”.")
         |> push_navigate(to: ~p"/browse")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:browse}>
      <.header>
        <.link navigate={~p"/browse"} class="text-base-content/45 hover:text-primary">Browse</.link>
        <span class="text-base-content/30">/</span>
        {@pack.name || @pack.code}
        <:subtitle>
          {product_type_label(@pack.product_type)}
          <span :if={@pack.wave}>
            · {@pack.wave.name}
          </span><span :if={@pack.released_on}>
            · {@pack.released_on.year}
          </span>
          · {@pack.card_total || 0} cards
        </:subtitle>
      </.header>

      <div class="flex flex-col gap-9">
        <.grouped_section
          title="Villains"
          description="Scenario villain sets included in this product."
          groups={@villain_groups}
        />

        <.grouped_section
          title="Encounter Sets"
          description="Standard, expert, and leader encounter sets included in this product."
          groups={@encounter_groups}
        />

        <.card_section
          :for={section <- @sections}
          title={section.title}
          subtitle={section.subtitle}
          cards={section.cards}
        />

        <.grouped_section
          title="Player Cards"
          description="Aspect and basic cards included in this product."
          groups={@player_groups}
        />

        <.grouped_section
          title="Modular Sets"
          description="Encounter modules included in this product."
          groups={@modular_groups}
        />
      </div>

      <.panel
        :if={
          @sections == [] and @villain_groups == [] and @encounter_groups == [] and
            @player_groups == [] and @modular_groups == []
        }
        class="mt-2 p-6 text-center"
      >
        <p class="font-barlow-condensed text-lg text-base-content/60">
          No cards have been synced for this product yet.
        </p>
      </.panel>
    </Layouts.app>
    """
  end

  # A yellow top-level category heading over one :sub card_section per group —
  # the shared shape for Villains, Player Cards, and Modular Sets.
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :groups, :list, required: true

  defp grouped_section(assigns) do
    ~H"""
    <section :if={@groups != []}>
      <h2 class={[
        "font-anton text-[22px] uppercase tracking-[0.03em] text-primary",
        (@description && "mb-1") || "mb-4"
      ]}>
        {@title}
      </h2>
      <p :if={@description} class="mb-4 font-barlow-condensed text-base-content/50">
        {@description}
      </p>
      <div class="flex flex-col gap-6">
        <.card_section :for={group <- @groups} title={group.title} cards={group.cards} level={:sub} />
      </div>
    </section>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :cards, :list, required: true
  attr :level, :atom, default: :top

  defp card_section(assigns) do
    ~H"""
    <section>
      <div class="mb-3.5 flex flex-wrap items-baseline gap-x-3 border-b-2 border-neutral pb-2">
        <h2 class={[
          "font-anton uppercase leading-none tracking-[0.03em]",
          @level == :top && "text-[22px] text-primary",
          @level == :sub && "text-[17px] text-base-content/85"
        ]}>
          {@title}
        </h2>
        <span :if={@subtitle} class="font-barlow-condensed text-base uppercase text-base-content/45">
          {@subtitle}
        </span>
        <span class="ml-auto font-ibm-mono text-[11px] text-base-content/40">
          {Enum.sum_by(@cards, & &1.quantity)} cards
        </span>
      </div>

      <div class="flex flex-wrap gap-2.5">
        <.link
          :for={card <- @cards}
          navigate={~p"/cards/#{card.card_id}"}
          class={
            [
              "h-[210px] flex-none border-2 border-neutral shadow-comic-sm",
              # Fixed height keeps every card's baseline aligned; the width follows
              # the card's real aspect (7/5 landscape vs 5/7 portrait) so mc_card's
              # object-cover image shows the full scan without cropping.
              (card.is_landscape && "w-[294px]") || "w-[150px]"
            ]
          }
        >
          <.mc_card
            name={card.name}
            type={card.type}
            aspect={card.aspect_key}
            resources={card.resources}
            qty={card.quantity}
            image_url={card.image_url}
            gradient_from={card.gradient_from}
            gradient_to={card.gradient_to}
            size="md"
            show_cost={false}
          />
        </.link>
      </div>
    </section>
    """
  end

  # The flat middle sections: Main Scheme, then each hero followed by its
  # nemesis. Villains, encounter sets, and modular sets render as their own
  # grouped blocks (see *_groups/2). Nemesis sets whose hero is in this product
  # render right after that hero; orphaned nemesis sets render standalone.
  defp build_sections(pack, hero_colors) do
    sets = pack.card_sets
    hero_sets = Enum.filter(sets, &(&1.set_type == :hero))
    paired_nemesis_ids = nemesis_ids_for(sets, hero_sets)

    main_scheme_sections =
      case cards_of_type(sets, :main_scheme, hero_colors) do
        [] -> []
        cards -> [%{title: "Main Scheme", subtitle: nil, cards: cards}]
      end

    hero_sections = Enum.flat_map(hero_sets, &hero_and_nemesis_sections(&1, sets, hero_colors))

    standalone_nemesis =
      sets
      |> Enum.filter(&(&1.set_type == :nemesis and &1.id not in paired_nemesis_ids))
      |> Enum.map(
        &%{
          title: &1.name || "Nemesis",
          subtitle: "Nemesis",
          cards: view_cards(&1.cards, hero_colors)
        }
      )

    main_scheme_sections ++ hero_sections ++ standalone_nemesis
  end

  # A hero and its nemesis render as adjacent-but-separate sections: the hero's
  # signature set, then its nemesis set right after.
  defp hero_and_nemesis_sections(hero_set, sets, hero_colors) do
    nemesis = Enum.find(sets, &(&1.set_type == :nemesis and &1.hero_set_id == hero_set.id))

    hero_section = %{
      title: hero_set.name || "Hero",
      subtitle: "Hero",
      cards: view_cards(hero_set.cards, hero_colors)
    }

    nemesis_section =
      if nemesis do
        [
          %{
            title: nemesis.name || "Nemesis",
            subtitle: "Nemesis",
            cards: view_cards(nemesis.cards, hero_colors)
          }
        ]
      else
        []
      end

    [hero_section | nemesis_section]
  end

  defp nemesis_ids_for(sets, hero_sets) do
    hero_ids = MapSet.new(hero_sets, & &1.id)

    for s <- sets, s.set_type == :nemesis, s.hero_set_id in hero_ids, into: MapSet.new(), do: s.id
  end

  defp cards_of_type(sets, type, hero_colors) do
    sets |> Enum.filter(&(&1.set_type == type)) |> cards_from_sets(hero_colors)
  end

  defp cards_from_sets(sets, hero_colors) do
    sets |> Enum.flat_map(& &1.cards) |> view_cards(hero_colors)
  end

  # Encounter set types that make up the "Encounter Sets" block (standard/expert
  # difficulty sets, PvP "leader" sets, evidence sets).
  @encounter_set_types [:standard, :expert, :leader, :evidence]

  # One group per villain (scenario) set.
  defp villain_groups(pack, hero_colors), do: set_groups(pack, [:villain], hero_colors)

  # One group per encounter set (standard/expert/leader/evidence).
  defp encounter_groups(pack, hero_colors),
    do: set_groups(pack, @encounter_set_types, hero_colors)

  # One group per modular set (kept separate rather than merged).
  defp modular_groups(pack, hero_colors), do: set_groups(pack, [:modular], hero_colors)

  defp set_groups(pack, set_types, hero_colors) do
    pack.card_sets
    |> Enum.filter(&(&1.set_type in set_types))
    # Order by each set's lowest card code — roughly the pack's printed order, so
    # the headline set leads rather than whatever sorts alphabetically.
    |> Enum.sort_by(&min_card_code/1)
    |> Enum.map(&%{title: &1.name || &1.code, cards: view_cards(&1.cards, hero_colors)})
    |> Enum.reject(&(&1.cards == []))
  end

  defp min_card_code(%{cards: []}), do: ""
  defp min_card_code(%{cards: cards}), do: cards |> Enum.map(& &1.code) |> Enum.min()

  # Player/basic cards belong to no card set; bucket them by aspect.
  defp player_card_groups(pack, hero_colors) do
    cards =
      Sanctum.Games.Card
      |> Ash.Query.filter(pack_id == ^pack.id and is_nil(card_set_id))
      |> Ash.Query.load([:primary_side, :card_sides])
      |> Ash.read!()

    cards
    |> Enum.group_by(&display_aspect(&1.primary_side))
    |> Enum.sort_by(fn {aspect, _} -> Map.get(@aspect_order, aspect, 99) end)
    |> Enum.map(fn {aspect, cards} ->
      %{title: aspect_label(aspect), cards: view_cards(cards, hero_colors)}
    end)
  end

  defp view_cards(cards, hero_colors) do
    cards
    |> Enum.flat_map(&card_views(&1, hero_colors))
    |> Enum.sort_by(& &1.sort_key)
  end

  # Display maps for every side of a card. Single-sided cards yield one view;
  # multi-sided cards (identities, main schemes) yield one per face, primary
  # side first, so the pack page shows front and back.
  defp card_views(%{card_sides: sides} = card, hero_colors)
       when is_list(sides) and sides != [] do
    {gradient_from, gradient_to} = hero_gradient(card.set, hero_colors)

    sides
    |> Enum.sort_by(&{!&1.is_primary_side, &1.side_identifier || ""})
    |> Enum.map(fn side ->
      resources =
        [
          energy: side.resource_energy_count,
          mental: side.resource_mental_count,
          physical: side.resource_physical_count,
          wild: side.resource_wild_count
        ]
        |> Enum.flat_map(fn {res, n} -> List.duplicate(res, n || 0) end)

      %{
        card_id: card.id,
        code: side.code,
        # Keep a card's faces adjacent and primary-first, then order cards among
        # themselves by the canonical code.
        sort_key: {card.code, (side.is_primary_side && 0) || 1, side.side_identifier || ""},
        name: side.name,
        type: side.type,
        aspect_key: display_aspect(side),
        is_landscape: CardComponent.landscape_type?(side.type),
        resources: resources,
        # MarvelCDB's per-card `quantity` (copies in the product) is stored on
        # Card.deck_limit; show the ×N badge only on the primary face so a
        # double-sided card isn't counted twice in the section total.
        quantity: (side.is_primary_side && (card.deck_limit || 1)) || 0,
        gradient_from: gradient_from,
        gradient_to: gradient_to,
        image_url: side.image_url
      }
    end)
  end

  defp card_views(_card, _hero_colors), do: []

  defp hero_gradient(set, hero_colors) do
    case Map.get(hero_colors, set) do
      {from, to} when is_binary(from) and is_binary(to) -> {from, to}
      _ -> CardComponent.fallback_gradient(set)
    end
  end

  # Mirrors CardLive.Pool: aspect cards use their aspect; other pools use
  # ownership; encounter/campaign share the encounter accent.
  defp display_aspect(nil), do: :basic
  defp display_aspect(%{ownership: :player, aspect: aspect}) when not is_nil(aspect), do: aspect
  defp display_aspect(%{ownership: :hero}), do: :hero
  defp display_aspect(%{ownership: :basic}), do: :basic
  defp display_aspect(%{ownership: :encounter}), do: :encounter
  defp display_aspect(%{ownership: :campaign}), do: :encounter
  defp display_aspect(%{aspect: aspect}) when not is_nil(aspect), do: aspect
  defp display_aspect(_), do: :basic

  defp aspect_label(:hero), do: "Hero"
  defp aspect_label(:encounter), do: "Encounter"
  defp aspect_label(aspect), do: aspect |> to_string() |> String.capitalize()

  defp product_type_label(:core), do: "Core Set"
  defp product_type_label(:campaign_expansion), do: "Campaign Expansion"
  defp product_type_label(:hero_pack), do: "Hero Pack"
  defp product_type_label(:scenario_pack), do: "Scenario Pack"
  defp product_type_label(:promo), do: "Promo"
  defp product_type_label(_), do: "Product"
end
