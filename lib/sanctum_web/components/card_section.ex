defmodule SanctumWeb.Components.CardSection do
  @moduledoc """
  A titled grid of compact card images — the grouped-contents block shared by
  a product page (`/browse/:pack`) and a public homebrew set page
  (`/custom/@username/:slug`).

  Each card is a display map with `card_id`, `name`, `type`, `aspect_key`,
  `resources`, `quantity`, `image_url`, `gradient_from`, `gradient_to` and
  `is_landscape` (see `SanctumWeb.Components.CardSideTile.side_view/2` plus a
  `quantity`).
  """

  use SanctumWeb, :html

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :cards, :list, required: true
  attr :level, :atom, default: :top
  attr :owned_ids, :any, default: nil, doc: "MapSet of owned card ids; nil hides collection UI"

  attr :count, :integer,
    default: nil,
    doc: "card count shown in the heading; defaults to the sum of the cards' quantities"

  attr :link?, :boolean,
    default: true,
    doc: "link each card to /cards/:id (off where the detail page wouldn't resolve)"

  attr :anchor, :string,
    default: nil,
    doc: "DOM id for the section, so a URL fragment (e.g. /browse/:pack#<code>) can land here"

  def card_section(assigns) do
    assigns =
      assign(assigns, :count_label, assigns.count || Enum.sum_by(assigns.cards, & &1.quantity))

    ~H"""
    <section id={@anchor} class="scroll-mt-24 lg:scroll-mt-6">
      <div class="mb-3.5 flex flex-wrap items-baseline gap-x-3 border-b-2 border-neutral pb-2">
        <h2 class={[
          "font-anton uppercase leading-none tracking-[0.03em]",
          @level == :top && "text-2xl text-primary",
          @level == :sub && "text-lg text-base-content/85"
        ]}>
          {@title}
        </h2>
        <span :if={@subtitle} class="font-barlow-condensed text-base uppercase text-base-content/45">
          {@subtitle}
        </span>
        <span class="ml-auto font-ibm-mono text-xs text-base-content/40">
          {@count_label} cards
        </span>
      </div>

      <div class="flex flex-wrap gap-2.5">
        <div
          :for={card <- @cards}
          class={
            [
              "relative h-[210px] flex-none",
              # Fixed height keeps every card's baseline aligned; the width follows
              # the card's real aspect (7/5 landscape vs 5/7 portrait) so mc_card's
              # object-cover image shows the full scan without cropping.
              (card.is_landscape && "w-[294px]") || "w-[150px]"
            ]
          }
        >
          <.link
            :if={@link?}
            navigate={~p"/cards/#{card.card_id}"}
            class="block h-full w-full border-2 border-neutral shadow-comic-sm"
          >
            <.section_card card={card} />
          </.link>
          <div :if={!@link?} class="block h-full w-full border-2 border-neutral shadow-comic-sm">
            <.section_card card={card} />
          </div>
          <.collection_toggle
            :if={@owned_ids && card.quantity > 0}
            compact
            owned={MapSet.member?(@owned_ids, card.card_id)}
            event="toggle_card_owned"
            id={card.card_id}
            class="absolute bottom-1.5 right-1.5 z-10"
          />
        </div>
      </div>
    </section>
    """
  end

  attr :card, :map, required: true

  defp section_card(assigns) do
    ~H"""
    <.mc_card
      name={@card.name}
      type={@card.type}
      aspect={@card.aspect_key}
      resources={@card.resources}
      qty={@card.quantity}
      image_url={@card.image_url}
      gradient_from={@card.gradient_from}
      gradient_to={@card.gradient_to}
      size="md"
      show_cost={false}
    />
    """
  end
end
