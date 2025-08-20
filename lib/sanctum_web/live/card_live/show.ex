defmodule SanctumWeb.CardLive.Show do
  use SanctumWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Card {@card.id}
        <:subtitle>This is a card record from your database.</:subtitle>

        <:actions>
          <.button navigate={~p"/cards"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/cards/#{@card}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit Card
          </.button>
        </:actions>
      </.header>

      <div class="mb-6">
        <img src={@card.image_url} alt={@card.name} class="w-64 h-auto rounded-lg shadow-lg" />
      </div>

      <.list>
        <:item title="Name">{@card.name}</:item>
        <:item :if={@card.subname} title="Subname">{@card.subname}</:item>
        <:item title="Code">{@card.code}</:item>
        <:item :if={@card.type} title="Type">{@card.type}</:item>
        <:item :if={@card.aspect} title="Aspect">{@card.aspect}</:item>
        <:item :if={@card.cost} title="Cost">{@card.cost}</:item>
        <:item :if={@card.text} title="Text">{@card.text}</:item>
        <:item :if={@card.traits && @card.traits != []} title="Traits">
          {Enum.join(@card.traits, ", ")}
        </:item>
        <:item :if={@card.attack} title="Attack">{@card.attack}</:item>
        <:item :if={@card.attack_cost} title="Attack Cost">{@card.attack_cost}</:item>
        <:item :if={@card.thwart} title="Thwart">{@card.thwart}</:item>
        <:item :if={@card.thwart_cost} title="Thwart Cost">{@card.thwart_cost}</:item>
        <:item :if={@card.defense} title="Defense">{@card.defense}</:item>
        <:item :if={@card.defense_cost} title="Defense Cost">{@card.defense_cost}</:item>
        <:item :if={@card.health} title="Health">{@card.health}</:item>
        <:item :if={@card.deck_limit} title="Deck Limit">{@card.deck_limit}</:item>
        <:item title="Unique">{if @card.unique, do: "Yes", else: "No"}</:item>
        <:item title="Permanent">{if @card.permanent, do: "Yes", else: "No"}</:item>
        <:item :if={@card.acceleration_icon} title="Acceleration Icon">Yes</:item>
        <:item :if={@card.amplify_icon} title="Amplify Icon">Yes</:item>
        <:item :if={@card.crisis_icon} title="Crisis Icon">Yes</:item>
        <:item :if={@card.hazard_icon} title="Hazard Icon">Yes</:item>
        <:item
          :if={@card.resource_energy_count && @card.resource_energy_count > 0}
          title="Energy Resources"
        >
          {@card.resource_energy_count}
        </:item>
        <:item
          :if={@card.resource_physical_count && @card.resource_physical_count > 0}
          title="Physical Resources"
        >
          {@card.resource_physical_count}
        </:item>
        <:item
          :if={@card.resource_mental_count && @card.resource_mental_count > 0}
          title="Mental Resources"
        >
          {@card.resource_mental_count}
        </:item>
        <:item :if={@card.resource_wild_count && @card.resource_wild_count > 0} title="Wild Resources">
          {@card.resource_wild_count}
        </:item>
        <:item :if={@card.hand_size} title="Hand Size">{@card.hand_size}</:item>
        <:item :if={@card.recover} title="Recover">{@card.recover}</:item>
        <:item :if={@card.health_per_hero} title="Health Per Hero">Yes</:item>
        <:item :if={@card.stage} title="Stage">{@card.stage}</:item>
        <:item :if={@card.base_threat} title="Base Threat">{@card.base_threat}</:item>
        <:item :if={@card.escalation_threat} title="Escalation Threat">
          {@card.escalation_threat}
        </:item>
        <:item :if={@card.boost} title="Boost">{@card.boost}</:item>
        <:item :if={@card.boost_star} title="Boost Star">Yes</:item>
        <:item :if={@card.card_set} title="Card Set">{@card.card_set}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Card")
     |> assign(:card, Ash.get!(Sanctum.Games.Card, id, actor: socket.assigns.current_user))}
  end
end
