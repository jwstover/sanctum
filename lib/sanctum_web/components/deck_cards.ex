defmodule SanctumWeb.Components.DeckCards do
  @moduledoc """
  Shared presentation for deck card lists (the deck detail page and the
  builder's deck panel): the per-card display-map builder, type grouping,
  the images/list view toggle, and the localStorage view-preference hook.

  Both surfaces render the same shapes so the deck reads identically whether
  you're viewing or building it.
  """

  use Phoenix.Component

  import SanctumWeb.CoreComponents, only: [icon: 1]

  alias SanctumWeb.Components.Card, as: CardComponent
  alias SanctumWeb.Components.ChampionsIcons

  @type_order [:ally, :event, :support, :upgrade, :resource, :player_side_scheme]
  @type_labels %{
    ally: "Allies",
    event: "Events",
    support: "Supports",
    upgrade: "Upgrades",
    resource: "Resources",
    player_side_scheme: "Side Schemes"
  }

  @doc """
  Builds the display map for one deck entry — a loaded `DeckCard` or any map
  shaped like `%{card: card, quantity: n}` with the card's `:primary_side`
  loaded. `hero_gradient` paints hero-aspect tiles (`{from, to}`).
  """
  def card_view(%{card: card, quantity: qty}, hero_gradient) do
    side = card.primary_side
    aspect_key = display_aspect(side)
    {gf, gt} = if aspect_key == :hero, do: hero_gradient, else: {nil, nil}

    %{
      card_id: card.id,
      qty: qty,
      name: side.name,
      cost: CardComponent.display_value(side.cost),
      type: side.type,
      hero?: side.ownership == :hero,
      aspect_key: aspect_key,
      aspect_bg: CardComponent.aspect_classes(aspect_key).bg,
      pips: ChampionsIcons.resource_pips(side_resources(side)),
      image_url: side.image_url,
      gradient_from: gf,
      gradient_to: gt,
      max: if(card.unique, do: 1, else: card.deck_limit || 1),
      owned: owned_flag(card)
    }
  end

  @doc """
  Groups card views by card type in canonical order: `%{type, name, count,
  cards}` with quantities summed and names sorted within each group.
  """
  def group_by_type(card_views) do
    card_views
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, cards} ->
      %{
        type: type,
        name: type_label(type),
        count: Enum.sum(Enum.map(cards, & &1.qty)),
        cards: Enum.sort_by(cards, &String.downcase(&1.name))
      }
    end)
    |> Enum.sort_by(&type_rank(&1.type))
  end

  @doc """
  Player-card display key: aspect cards (including pool) use their aspect;
  hero/basic ownership pools use their ownership.
  """
  def display_aspect(%{ownership: :player, aspect: aspect}) when not is_nil(aspect), do: aspect
  def display_aspect(%{ownership: :hero}), do: :hero
  def display_aspect(%{ownership: :basic}), do: :basic
  def display_aspect(%{aspect: aspect}) when not is_nil(aspect), do: aspect
  def display_aspect(_side), do: :basic

  @doc "One resource atom per printed pip on the side."
  def side_resources(side) do
    [
      energy: side.resource_energy_count,
      mental: side.resource_mental_count,
      physical: side.resource_physical_count,
      wild: side.resource_wild_count
    ]
    |> Enum.flat_map(fn {res, n} -> List.duplicate(res, n || 0) end)
  end

  @doc "The hero's `{from, to}` border gradient, falling back per set slug."
  def hero_gradient(%{primary_color: from, secondary_color: to, set: set}) do
    {fallback_from, fallback_to} = CardComponent.fallback_gradient(set)
    {from || fallback_from, to || fallback_to}
  end

  @doc "The hero identity art: the hero side's scan, then the primary side's."
  def identity_image(%{hero_side: %{image_url: url}}) when is_binary(url), do: url
  def identity_image(%{card: %{primary_side: %{image_url: url}}}) when is_binary(url), do: url
  def identity_image(_hero), do: nil

  @doc """
  Handles the shared `set_card_view` / `restore_card_view` events. Call from
  a `handle_event/3` clause and wrap the result in `{:noreply, socket}`.
  """
  def handle_card_view_event("set_card_view", %{"view" => view}, socket)
      when view in ~w(images list) do
    socket
    |> Phoenix.Component.assign(:card_view, view)
    |> Phoenix.LiveView.push_event("store_card_view", %{view: view})
  end

  def handle_card_view_event("restore_card_view", %{"view" => view}, socket)
      when view in ~w(images list) do
    Phoenix.Component.assign(socket, :card_view, view)
  end

  def handle_card_view_event(_event, _params, socket), do: socket

  @doc "Display chips for a deck's aspect list (empty = a basic deck)."
  def aspect_badges([]), do: [aspect_badge(:basic, "Basic")]

  def aspect_badges(aspects),
    do: Enum.map(aspects, &aspect_badge(&1, &1 |> to_string() |> String.capitalize()))

  defp aspect_badge(aspect, label) do
    ac = CardComponent.aspect_classes(aspect)
    %{label: label, text: ac.text, border: ac.border}
  end

  @doc """
  Lifecycle chips for a deck: "Draft" and/or "Private" when the deck hasn't
  completed the phased flow. Final + published decks (the norm — every
  imported deck) render nothing. Only owners ever see these — private decks
  are policy-filtered for everyone else.
  """
  attr :state, :atom, required: true
  attr :visibility, :atom, required: true

  def deck_status_badges(assigns) do
    ~H"""
    <span
      :if={@state == :draft}
      class="border-2 border-warning/60 bg-black px-2 py-0.5 font-barlow-condensed text-xs font-bold uppercase tracking-[0.08em] text-warning"
    >
      Draft
    </span>
    <span
      :if={@visibility == :private}
      class="border-2 border-neutral bg-black px-2 py-0.5 font-barlow-condensed text-xs font-bold uppercase tracking-[0.08em] text-base-content/60"
    >
      Private
    </span>
    """
  end

  @doc "Human label for a deck's source."
  def source_label(:marvelcdb), do: "MarvelCDB"
  def source_label(:native), do: "Native"
  def source_label(other), do: other |> to_string() |> String.capitalize()

  @doc """
  Attribution: imported decks credit the MarvelCDB author; native decks
  credit the owner's claimed username (never their email — the field is
  policy-hidden). Owners without a username get no attribution row.
  """
  def author(%{mcdb_user: %{username: username}}) when is_binary(username) and username != "",
    do: %{name: "@" <> username, avatar: nil}

  def author(%{mcdb_user: %{mcdb_user_id: id}}) when not is_nil(id),
    do: %{name: "mcdb ##{id}", avatar: nil}

  def author(%{owner: %{username: %Ash.CiString{} = username, avatar_url: avatar}}),
    do: %{name: "@" <> to_string(username), avatar: avatar}

  def author(_deck), do: nil

  # true/false only when the :owned calc was loaded (signed-in); nil renders
  # no collection UI.
  defp owned_flag(card) do
    case Map.get(card, :owned) do
      value when is_boolean(value) -> value
      _not_loaded -> nil
    end
  end

  defp type_label(type),
    do: Map.get(@type_labels, type, type |> to_string() |> String.capitalize())

  defp type_rank(type) do
    Enum.find_index(@type_order, &(&1 == type)) || length(@type_order)
  end

  @doc """
  Cost column for list rows — the card pool's cost treatment (plain
  `font-elektra-med` numeral) at row scale. Costless cards (resources)
  render an invisible placeholder so name columns stay aligned.
  """
  attr :cost, :any, required: true

  def row_cost(assigns) do
    ~H"""
    <span class="w-5 flex-none text-center font-elektra-med text-base leading-none text-base-content/90">
      {@cost}
    </span>
    """
  end

  @doc """
  One half of the images/list segmented toggle. Emits `set_card_view` with
  `phx-value-view`; pair it with `<.card_view_pref />` so the choice persists.
  """
  attr :view, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, required: true

  def view_toggle_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="set_card_view"
      phx-value-view={@view}
      aria-label={@label}
      aria-pressed={to_string(@active)}
      title={@label}
      class={[
        "flex size-7 items-center justify-center transition-colors",
        if(@active,
          do: "bg-primary text-primary-content",
          else: "text-base-content/50 hover:bg-base-200 hover:text-base-content"
        )
      ]}
    >
      <.icon name={@icon} class="size-4" />
    </button>
    """
  end

  @doc """
  Invisible hook element persisting the images/list preference in
  localStorage, shared across every deck surface. The host LiveView handles
  `set_card_view` (assign + `push_event("store_card_view", ...)`) and
  `restore_card_view` (assign only).
  """
  attr :id, :string, default: "deck-card-view-pref"

  def card_view_pref(assigns) do
    ~H"""
    <div id={@id} phx-hook=".CardViewPref"></div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".CardViewPref">
      const KEY = "sanctum:deck-card-view"

      export default {
        mounted() {
          const stored = localStorage.getItem(KEY)
          if (stored === "list" || stored === "images") {
            this.pushEvent("restore_card_view", {view: stored})
          }
          this.handleEvent("store_card_view", ({view}) => {
            localStorage.setItem(KEY, view)
          })
        }
      }
    </script>
    """
  end
end
