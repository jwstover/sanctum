defmodule SanctumWeb.DeckLive.Show do
  @moduledoc """
  Public deck detail — a comic-dossier "decklist" view: a cover with the hero
  identity card + deck meta, the writeup, and the card list grouped by type.
  """
  use SanctumWeb, :live_view

  alias SanctumWeb.Components.Card, as: CardComponent

  @type_order [:ally, :event, :support, :upgrade, :resource]
  @type_plural %{
    ally: "Allies",
    event: "Events",
    support: "Supports",
    upgrade: "Upgrades",
    resource: "Resources"
  }

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:decks}>
      <.header>
        {@deck.title}
        <:subtitle>
          {@cover.hero_name}<span :if={@cover.author}> · by {@cover.author}</span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/decks"}>
            <.icon name="hero-arrow-left" /> Decks
          </.button>
        </:actions>
      </.header>

      <div class="space-y-5">
        <!-- cover -->
        <.panel class="relative flex flex-col gap-5 overflow-hidden p-4 sm:flex-row sm:items-start">
          <div
            class="h-[330px] w-[236px] flex-none self-center border-2 border-neutral shadow-comic sm:self-start"
            style="transform:rotate(-1.5deg);"
          >
            <.mc_card
              name={@cover.hero_name}
              aspect={:hero}
              image_url={@cover.identity_image}
              gradient_from={@cover.gradient_from}
              gradient_to={@cover.gradient_to}
              size="lg"
              show_cost={false}
            />
          </div>

          <div class="flex min-w-0 flex-1 flex-col">
            <div class="font-ibm-mono text-[11px] uppercase tracking-[0.25em] text-primary">
              {@cover.source_label} · {@cover.hero_name}
            </div>
            <h1 class="mt-1.5 font-anton text-[34px] uppercase leading-[0.9] [text-wrap:balance] sm:text-[46px] sm:leading-[0.88]">
              {@deck.title}
            </h1>

            <div class="mt-3 flex flex-wrap items-center gap-1.5">
              <span
                :for={a <- @cover.aspects}
                class={[
                  "border-2 bg-black px-2 py-0.5 font-barlow-condensed text-[11px] font-bold uppercase tracking-[0.08em]",
                  a.text,
                  a.border
                ]}
              >
                {a.label}
              </span>
            </div>

            <div class="mt-4 flex flex-wrap items-end gap-x-6 gap-y-3">
              <div>
                <div class="font-anton text-[30px] leading-none">{@cover.total_cards}</div>
                <div class="mt-1 font-barlow-condensed text-[11px] font-bold uppercase tracking-[0.1em] text-base-content/50">
                  Cards
                </div>
              </div>
              <div>
                <div class="font-anton text-[30px] leading-none">{@cover.unique_cards}</div>
                <div class="mt-1 font-barlow-condensed text-[11px] font-bold uppercase tracking-[0.1em] text-base-content/50">
                  Unique
                </div>
              </div>
              <.uniqueness_meter percentile={@cover.uniqueness} size="lg" class="self-center" />
              <div :if={@cover.author} class="flex items-center gap-2 self-center">
                <span class="flex size-[28px] items-center justify-center rounded-full border-2 border-neutral bg-primary font-bangers text-sm text-primary-content">
                  {@cover.author_initial}
                </span>
                <span class="font-barlow-condensed text-[13px] font-bold text-primary">
                  {@cover.author}
                </span>
              </div>
            </div>
          </div>
          <div class="absolute inset-x-0 bottom-0 h-1.5" style={"background:#{@cover.gradient_to};"}>
          </div>
        </.panel>

        <!-- body: writeup + card list -->
        <div class="grid items-start gap-5 lg:grid-cols-[1.4fr_1fr]">
          <.panel class="min-w-0 p-5">
            <div class="mb-3 font-ibm-mono text-[10px] uppercase tracking-[0.2em] text-base-content/50">
              Deck Notes
            </div>
            <div :if={@writeup} class="space-y-4">
              <div :for={seg <- @writeup}>
                <div :if={seg.kind == :inline} class="deck-writeup">{seg.html}</div>
                <iframe
                  :if={seg.kind == :rich}
                  title="Deck writeup"
                  sandbox=""
                  referrerpolicy="no-referrer"
                  loading="lazy"
                  class="deck-writeup-frame"
                  srcdoc={seg.srcdoc}
                ></iframe>
              </div>
            </div>
            <div :if={!@writeup} class="font-barlow text-[14px] italic text-base-content/45">
              No writeup for this deck.
            </div>
          </.panel>

          <div class="min-w-0 space-y-5">
            <.panel class="p-4">
              <div class="mb-3 flex items-baseline gap-2 border-b-2 border-neutral pb-2">
                <div class="font-anton text-[17px] uppercase tracking-[0.05em]">In This Deck</div>
                <div class="ml-auto font-ibm-mono text-[11px] text-base-content/45">
                  {@cover.total_cards} cards
                </div>
              </div>

              <div :for={g <- @groups} class="mb-4 last:mb-0">
                <div class="mb-2 font-anton text-[12px] uppercase tracking-[0.06em] text-primary">
                  {g.name} · {g.count}
                </div>
                <div class="grid grid-cols-[repeat(auto-fill,minmax(72px,1fr))] gap-2">
                  <.link
                    :for={c <- g.cards}
                    navigate={~p"/admin/cards/#{c.card_id}"}
                    class="h-[101px] border-2 border-neutral shadow-comic-sm"
                  >
                    <.mc_card
                      name={c.name}
                      cost={c.cost}
                      aspect={c.aspect_key}
                      image_url={c.image_url}
                      gradient_from={c.gradient_from}
                      gradient_to={c.gradient_to}
                      qty={c.qty}
                      size="sm"
                      show_cost={false}
                    />
                  </.link>
                </div>
              </div>
            </.panel>

            <!-- similar decks -->
            <.panel :if={@similar != []} class="p-4">
              <div class="mb-3 font-ibm-mono text-[10px] uppercase tracking-[0.2em] text-base-content/50">
                Similar Decks
              </div>
              <div class="space-y-2">
                <.link
                  :for={s <- @similar}
                  navigate={~p"/decks/#{s.id}"}
                  class="mc-tile flex items-center gap-3 border-2 border-neutral bg-black p-2.5 shadow-comic-sm"
                >
                  <div class="min-w-0 flex-1">
                    <div class="truncate font-anton text-[16px] uppercase leading-tight">
                      {s.title}
                    </div>
                    <div class="mt-1 flex flex-wrap gap-1">
                      <span
                        :for={a <- s.aspects}
                        class={[
                          "border bg-base-200 px-1.5 font-barlow-condensed text-[10px] font-bold uppercase tracking-[0.06em]",
                          a.text,
                          a.border
                        ]}
                      >
                        {a.label}
                      </span>
                    </div>
                  </div>
                  <div class="flex-none text-right">
                    <div class="font-anton text-[20px] leading-none text-primary">{s.match}%</div>
                    <div class="font-barlow-condensed text-[10px] font-bold uppercase tracking-[0.1em] text-base-content/45">
                      Match
                    </div>
                  </div>
                </.link>
              </div>
            </.panel>

            <!-- details -->
            <.panel class="p-4">
              <div class="mb-3 font-ibm-mono text-[10px] uppercase tracking-[0.2em] text-base-content/50">
                Details
              </div>
              <div class="grid grid-cols-2 gap-x-6 gap-y-3">
                <.meta label="Source" value={@cover.source_label} />
                <.meta
                  :if={@deck.mcdb_id}
                  label="MarvelCDB"
                  value={"#{@deck.mcdb_type}/#{@deck.mcdb_id}"}
                />
                <.meta :if={@deck.version} label="Version" value={@deck.version} />
                <.meta :if={@deck.tags} label="Tags" value={@deck.tags} />
              </div>
            </.panel>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp meta(assigns) do
    ~H"""
    <div :if={@value not in [nil, ""]}>
      <div class="font-ibm-mono text-[10px] uppercase tracking-[0.2em] text-base-content/45">
        {@label}
      </div>
      <div class="mt-0.5 font-barlow-condensed text-[15px] font-semibold">{@value}</div>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    deck =
      Sanctum.Decks.get_deck!(id,
        actor: socket.assigns[:current_user],
        load: [
          :card_row_count,
          :total_card_count,
          :mcdb_user,
          :owner,
          hero: [:hero_side, card: [:primary_side]],
          deck_cards: [card: [:primary_side]]
        ]
      )

    hero_gradient = hero_gradient(deck.hero)

    groups =
      deck.deck_cards
      |> Enum.map(&card_view(&1, hero_gradient))
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {type, cards} ->
        %{
          type: type,
          name: type_plural(type),
          count: Enum.sum(Enum.map(cards, & &1.qty)),
          cards: Enum.sort_by(cards, &{&1.cost || 99, &1.name})
        }
      end)
      |> Enum.sort_by(&type_rank(&1.type))

    {:ok,
     socket
     |> assign(:page_title, deck.title)
     |> assign(:deck, deck)
     |> assign(:cover, cover_view(deck, hero_gradient))
     |> assign(:groups, groups)
     |> assign(:similar, similar_views(deck))
     |> assign(:writeup, Sanctum.Decks.Writeup.render(deck.description_md))}
  end

  # Same-hero decks that share the most chosen cards with this one.
  defp similar_views(deck) do
    deck
    |> Sanctum.Decks.Uniqueness.similar_decks(limit: 5)
    |> Enum.map(fn %{deck: d, similarity: sim} ->
      %{
        id: d.id,
        title: d.title,
        aspects: aspect_badges(d.aspects),
        card_count: d.total_card_count || 0,
        match: round(sim * 100)
      }
    end)
  end

  defp cover_view(deck, {gradient_from, gradient_to}) do
    hero = deck.hero
    author = author(deck)

    %{
      hero_name: hero.hero_name,
      identity_image: identity_image(hero),
      gradient_from: gradient_from,
      gradient_to: gradient_to,
      aspects: aspect_badges(deck.aspects),
      source_label: source_label(deck.source),
      total_cards: deck.total_card_count || 0,
      unique_cards: deck.card_row_count || 0,
      uniqueness: deck.uniqueness_percentile,
      author: author,
      author_initial: author_initial(author)
    }
  end

  defp card_view(dc, hero_gradient) do
    side = dc.card.primary_side
    aspect_key = display_aspect(side)
    {gf, gt} = if aspect_key == :hero, do: hero_gradient, else: {nil, nil}

    %{
      card_id: dc.card.id,
      qty: dc.quantity,
      name: side.name,
      cost: side.cost,
      type: side.type,
      aspect_key: aspect_key,
      image_url: side.image_url,
      gradient_from: gf,
      gradient_to: gt
    }
  end

  defp hero_gradient(%{primary_color: from, secondary_color: to, set: set}) do
    {fallback_from, fallback_to} = CardComponent.fallback_gradient(set)
    {from || fallback_from, to || fallback_to}
  end

  defp identity_image(%{hero_side: %{image_url: url}}) when is_binary(url), do: url
  defp identity_image(%{card: %{primary_side: %{image_url: url}}}) when is_binary(url), do: url
  defp identity_image(_), do: nil

  # Player-card aspect display key (aspect cards — including pool — use their
  # aspect; hero/basic ownership pools use their ownership).
  defp display_aspect(%{ownership: :player, aspect: aspect}) when not is_nil(aspect), do: aspect
  defp display_aspect(%{ownership: :hero}), do: :hero
  defp display_aspect(%{ownership: :basic}), do: :basic
  defp display_aspect(%{aspect: aspect}) when not is_nil(aspect), do: aspect
  defp display_aspect(_), do: :basic

  defp aspect_badges([]), do: [aspect_badge(:basic, "Basic")]

  defp aspect_badges(aspects),
    do: Enum.map(aspects, &aspect_badge(&1, &1 |> to_string() |> String.capitalize()))

  defp aspect_badge(aspect, label) do
    ac = CardComponent.aspect_classes(aspect)
    %{label: label, text: ac.text, border: ac.border}
  end

  defp source_label(:marvelcdb), do: "MarvelCDB"
  defp source_label(:native), do: "Native"
  defp source_label(other), do: other |> to_string() |> String.capitalize()

  defp author(%{mcdb_user: %{username: username}}) when is_binary(username) and username != "",
    do: "@" <> username

  defp author(%{mcdb_user: %{mcdb_user_id: id}}) when not is_nil(id), do: "mcdb ##{id}"
  defp author(%{owner: %{email: email}}) when is_binary(email), do: email
  defp author(_), do: nil

  defp author_initial(nil), do: "?"

  defp author_initial(author),
    do: author |> String.trim_leading("@") |> String.first() |> String.upcase()

  defp type_plural(type),
    do: Map.get(@type_plural, type, type |> to_string() |> String.capitalize())

  defp type_rank(type) do
    case Enum.find_index(@type_order, &(&1 == type)) do
      nil -> length(@type_order)
      i -> i
    end
  end
end
