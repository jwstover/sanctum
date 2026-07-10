defmodule SanctumWeb.CardLive.Show do
  use SanctumWeb, :live_view

  on_mount {SanctumWeb.LiveUserAuth, :live_user_optional}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash}>
      <.header>
        Card {assigns[:card] && @card.base_code}
        <:subtitle>
          <span
            :if={@card.is_multi_sided}
            class="inline-flex items-center px-2 py-1 text-xs font-medium text-blue-700 bg-blue-100 rounded-full mr-2"
          >
            Multi-sided
          </span>
          {length(@card.card_sides)} side(s)
        </:subtitle>

        <:actions>
          <.button navigate={~p"/cards"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/cards/#{@card}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit Card
          </.button>
        </:actions>
      </.header>
      
    <!-- Card-level information -->
      <div class="mb-8 p-6 bg-gray-50 rounded-lg">
        <h3 class="text-lg font-semibold mb-4">Card Information</h3>
        <.list>
          <:item title="Base Code">{@card.base_code}</:item>
          <:item title="Primary Code">{@card.code}</:item>
          <:item title="Multi-sided">{if @card.is_multi_sided, do: "Yes", else: "No"}</:item>
          <:item title="Deck Limit">{@card.deck_limit}</:item>
          <:item title="Unique">{if @card.unique, do: "Yes", else: "No"}</:item>
          <:item title="Permanent">{if @card.permanent, do: "Yes", else: "No"}</:item>
          <:item title="Set">{@card.set}</:item>
          <:item title="Pack">{@card.pack}</:item>
        </.list>
      </div>
      
    <!-- Card sides -->
      <div class="space-y-8">
        <div :for={side <- @card.card_sides} class="border rounded-lg p-6 bg-white shadow-sm">
          <div class="flex items-start gap-6">
            <div :if={side.image_url} class="flex-shrink-0">
              <img src={side.image_url} alt={side.name} class="w-64 h-auto rounded-lg shadow-lg" />
            </div>

            <div class="flex-1">
              <div class="flex items-center gap-2 mb-4">
                <h3 class="text-xl font-bold">{side.name}</h3>
                <span
                  :if={side.is_primary_side}
                  class="inline-flex items-center px-2 py-1 text-xs font-medium text-green-700 bg-green-100 rounded-full"
                >
                  Primary
                </span>
                <span class="inline-flex items-center px-2 py-1 text-xs font-medium text-gray-700 bg-gray-100 rounded-full">
                  Side {side.side_identifier}
                </span>
              </div>

              <.list>
                <:item title="Code">{side.code}</:item>
                <:item :if={side.subname} title="Subname">{side.subname}</:item>
                <:item :if={side.type} title="Type">{side.type}</:item>
                <:item :if={side.aspect} title="Aspect">{side.aspect}</:item>
                <:item :if={side.cost} title="Cost">{side.cost}</:item>
                <:item :if={side.text} title="Text">
                  <div class="prose prose-sm max-w-none">{side.text}</div>
                </:item>
                <:item :if={side.traits && side.traits != []} title="Traits">
                  {Enum.join(side.traits, ", ")}
                </:item>
                
    <!-- Combat Stats -->
                <div :if={side.attack || side.thwart || side.defense || side.health} class="mt-4">
                  <h4 class="text-sm font-semibold text-gray-700 mb-2">Combat Stats</h4>
                  <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
                    <div :if={side.attack} class="text-center p-2 bg-red-50 rounded">
                      <div class="text-lg font-bold text-red-700">{side.attack}</div>
                      <div class="text-xs text-red-600">Attack</div>
                    </div>
                    <div :if={side.thwart} class="text-center p-2 bg-blue-50 rounded">
                      <div class="text-lg font-bold text-blue-700">{side.thwart}</div>
                      <div class="text-xs text-blue-600">Thwart</div>
                    </div>
                    <div :if={side.defense} class="text-center p-2 bg-green-50 rounded">
                      <div class="text-lg font-bold text-green-700">{side.defense}</div>
                      <div class="text-xs text-green-600">Defense</div>
                    </div>
                    <div :if={side.health} class="text-center p-2 bg-yellow-50 rounded">
                      <div class="text-lg font-bold text-yellow-700">{side.health}</div>
                      <div class="text-xs text-yellow-600">Health</div>
                    </div>
                  </div>
                </div>
                
    <!-- Hero/Identity Stats -->
                <:item :if={side.hand_size} title="Hand Size">{side.hand_size}</:item>
                <:item :if={side.recover} title="Recover">{side.recover}</:item>
                
    <!-- Villain Stats -->
                <:item :if={side.health_per_hero} title="Health Per Hero">Yes</:item>
                <:item :if={side.stage} title="Stage">{side.stage}</:item>
                <:item :if={side.scheme} title="Scheme">{side.scheme}</:item>
                
    <!-- Scheme Stats -->
                <:item :if={side.base_threat} title="Base Threat">{side.base_threat}</:item>
                <:item :if={side.escalation_threat} title="Escalation Threat">
                  {side.escalation_threat}
                </:item>
                <:item :if={side.max_threat} title="Max Threat">{side.max_threat}</:item>
                
    <!-- Encounter Stats -->
                <:item :if={side.boost} title="Boost">{side.boost}</:item>
                <:item :if={side.boost_star} title="Boost Star">Yes</:item>
                
    <!-- Icons -->
                <div
                  :if={
                    side.acceleration_icon || side.amplify_icon || side.crisis_icon ||
                      side.hazard_icon
                  }
                  class="mt-4"
                >
                  <h4 class="text-sm font-semibold text-gray-700 mb-2">Icons</h4>
                  <div class="flex gap-2">
                    <span
                      :if={side.acceleration_icon}
                      class="px-2 py-1 text-xs bg-red-100 text-red-700 rounded"
                    >
                      Acceleration
                    </span>
                    <span
                      :if={side.amplify_icon}
                      class="px-2 py-1 text-xs bg-purple-100 text-purple-700 rounded"
                    >
                      Amplify
                    </span>
                    <span
                      :if={side.crisis_icon}
                      class="px-2 py-1 text-xs bg-orange-100 text-orange-700 rounded"
                    >
                      Crisis
                    </span>
                    <span
                      :if={side.hazard_icon}
                      class="px-2 py-1 text-xs bg-yellow-100 text-yellow-700 rounded"
                    >
                      Hazard
                    </span>
                  </div>
                </div>
                
    <!-- Resources -->
                <div
                  :if={
                    side.resource_energy_count || side.resource_physical_count ||
                      side.resource_mental_count || side.resource_wild_count
                  }
                  class="mt-4"
                >
                  <h4 class="text-sm font-semibold text-gray-700 mb-2">Resources</h4>
                  <div class="flex gap-2">
                    <span
                      :if={side.resource_energy_count && side.resource_energy_count > 0}
                      class="px-2 py-1 text-xs bg-yellow-100 text-yellow-700 rounded"
                    >
                      Energy: {side.resource_energy_count}
                    </span>
                    <span
                      :if={side.resource_physical_count && side.resource_physical_count > 0}
                      class="px-2 py-1 text-xs bg-red-100 text-red-700 rounded"
                    >
                      Physical: {side.resource_physical_count}
                    </span>
                    <span
                      :if={side.resource_mental_count && side.resource_mental_count > 0}
                      class="px-2 py-1 text-xs bg-blue-100 text-blue-700 rounded"
                    >
                      Mental: {side.resource_mental_count}
                    </span>
                    <span
                      :if={side.resource_wild_count && side.resource_wild_count > 0}
                      class="px-2 py-1 text-xs bg-gray-100 text-gray-700 rounded"
                    >
                      Wild: {side.resource_wild_count}
                    </span>
                  </div>
                </div>
              </.list>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    card =
      Ash.get!(Sanctum.Games.Card, id,
        actor: socket.assigns[:current_user],
        load: [:card_sides, :primary_side]
      )

    {:ok,
     socket
     |> assign(:page_title, "Show Card - #{card.base_code}")
     |> assign(:card, card)}
  end
end
