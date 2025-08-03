defmodule SanctumWeb.GameLive.Show do
  @moduledoc false

  use SanctumWeb, :live_view

  import SanctumWeb.GameLive.GameComponents

  alias Sanctum.Games

  def mount(%{"id" => game_id}, _session, socket) do
    {:ok,
     socket
     |> assign(
       :game,
       Games.get_game!(game_id, load: [:hero, :villian, :main_scheme])
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.game flash={@flash}>
      <div id="game-board" class="h-full overflow-hidden grid grid-cols-4 gap-4" phx-hook="CardDrag">
        <div
          id="side-schema-area"
          class="flex flex-row items-center justify-center border border-black"
        >
          Side Schemes
        </div>
        <div id="villian-area" class="flex flex-row items-center justify-center border border-red-500">
          <.card card={@game.villian} />
        </div>
        <div
          id="main-schema-area"
          class="flex flex-row items-center justify-center border border-black"
        >
          <.card card={@game.main_scheme} />
        </div>
        <div
          id="encounter-deck-area"
          class="flex flex-row items-center justify-center border border-black"
        >
          <.encounter_back />
        </div>
        <div
          id="encounter-area"
          class="col-span-4 flex flex-row items-center justify-center bg-orange-300/5 rounded border-4 border-gray-100/10"
        >
          <div class="text-3xl font-komika opacity-50">
            Encounter Area
          </div>
        </div>
        <div
          id="player-area"
          class="col-span-4 flex flex-row items-center justify-center bg-blue-300/5 rounded border-4 border-gray-100/10"
        >
          <div class="text-3xl font-komika opacity-50">
            Player Area
          </div>
        </div>

        <div
          id="player-side-schema-area"
          class="flex flex-row items-center justify-center bg-blue-300/5 rounded border-4 border-gray-100/10"
        >
        </div>

        <div
          id="hero-area"
          class="flex flex-row items-center justify-center bg-blue-300/5 rounded border-4 border-gray-100/10"
        >
          <.card card={@game.hero} />
        </div>
        <div
          id="player-deck-area"
          class="flex flex-row items-center justify-center bg-blue-300/5 rounded border-4 border-gray-100/10"
        >
        </div>
      </div>
    </Layouts.game>
    """
  end
end
