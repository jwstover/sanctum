defmodule SanctumWeb.GameLive.Show do
  @moduledoc false

  use SanctumWeb, :live_view

  import SanctumWeb.GameLive.GameComponents

  alias Sanctum.Games.GamePlayer
  alias Sanctum.Games
  alias Sanctum.Games.Game

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  def mount(%{"id" => game_id}, _session, socket) do
    {:ok,
     socket
     |> assign(%{
       game_id: game_id,
       show_player_form: false
     })
     |> assign_game()
     |> assign_game_player()}
  end

  def handle_info({:deck_selected, _game_player}, socket) do
    {:noreply,
     socket
     |> assign_game_player()
     |> assign(:show_player_form, false)}
  end

  def handle_event("card-dropped", %{"card" => game_card_id, "zone" => zone_name}, socket) do
    user = socket.assigns.current_user
    game_card = Games.get_game_card!(game_card_id, actor: user)

    Games.move_game_card(game_card, %{zone: zone_name}, actor: user)
    |> IO.inspect()

    {:noreply, socket |> assign_game_player()}
  end

  def handle_event("show-player-form", _params, socket) do
    {:noreply, assign(socket, :show_player_form, true)}
  end

  def handle_event("draw-1", _params, socket) do
    game_player = socket.assigns.game_player

    Games.draw_cards(game_player.id, 1, game_player.current_hand_size,
      actor: socket.assigns.current_user
    )

    {:noreply, socket |> assign_game_player()}
  end

  def handle_event("draw-hand", _params, socket) do
    game_player = socket.assigns.game_player

    count =
      game_player.max_hand_size - game_player.current_hand_size

    count > 0 &&
      Games.draw_cards(
        game_player.id,
        count,
        game_player.current_hand_size,
        actor: socket.assigns.current_user
      )

    {:noreply, socket |> assign_game_player()}
  end

  def handle_event("flip-hero", _params, socket) do
    game_player = socket.assigns.game_player

    Games.flip_identity(game_player)

    {:noreply, socket |> assign_game_player()}
  end

  @spec assign_game(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_game(%{assigns: %{game_id: game_id, current_user: current_user}} = socket)
       when is_binary(game_id) do
    case Games.get_game(game_id,
           load: [game_villian: [:card], game_schemes: [:card]],
           actor: current_user
         ) do
      {:ok, %Game{} = game} -> assign(socket, :game, game)
      {:error, _err} -> push_navigate(socket, to: ~p"/")
    end
  end

  defp assign_game_player(socket) do
    game = socket.assigns.game

    assign(
      socket,
      :game_player,
      Games.get_game_player!(game.id,
        load: [
          :deck_cards,
          :current_hand_size,
          :max_hand_size,
          :hand_size,
          hero_play_cards: [:card],
          hand_cards: [:card],
          deck: [:hero, :alter_ego]
        ],
        actor: socket.assigns.current_user
      )
    )
  end

  def render(assigns) do
    ~H"""
    <Layouts.game flash={@flash}>
      <.live_component
        :if={!@game_player.deck_id || @show_player_form}
        id="player-deck-form"
        module={SanctumWeb.GameLive.NewPlayerComponent}
        current_user={@current_user}
        game_player={@game_player}
      />
      <.play_area game={@game} game_player={@game_player} />
    </Layouts.game>
    """
  end

  attr :game, Game, required: true
  attr :game_player, GamePlayer, required: true

  def play_area(assigns) do
    ~H"""
    <div
      id="game-board"
      class="h-full overflow-x-hidden overflow-y-auto grid grid-rows-[auto_repeat(5,1fr)] grid-cols-4 gap-4"
    >
      <div class="col-span-4">
        <.menu_dropdown />
      </div>
      <div
        id="side-schema-area"
        class="flex flex-row items-center justify-center border border-black"
      >
        Side Schemes
      </div>
      <div id="villain-area" class="flex flex-row items-center justify-center border border-red-500">
        <.card id={@game.game_villian.card.id} card={@game.game_villian.card} />
      </div>
      <div
        id="main-schema-area"
        class="flex flex-row items-center justify-center border border-black"
      >
        <.card
          :for={main_scheme <- @game.game_schemes}
          id={main_scheme.card.id}
          card={main_scheme.card}
        />
      </div>
      <div
        id="encounter-deck-area"
        class="flex flex-row items-center justify-center border border-black"
      >
        <.encounter_back id="encounter-deck" />
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
        class="col-span-4 relative flex flex-row flex-wrap items-center justify-center bg-blue-300/5 rounded border-4 border-gray-100/10"
        phx-hook="DragDrop"
        data-drop_zone="hero_play"
      >
        <div class="absolute top-0 left-0 w-full h-full flex items-center justify-center text-3xl font-komika opacity-50">
          Player Area
        </div>
        <.card :for={card <- @game_player.hero_play_cards} id={card.id} card={card.card} />
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
        <.identity game_player={@game_player} />
      </div>
      <div
        id="player-deck-area"
        class="flex flex-row items-center justify-center bg-blue-300/5 rounded border-4 border-gray-100/10"
      >
        <.deck deck_cards={@game_player.deck_cards} />
      </div>
      <div></div>

      <div
        id="player-hand-area"
        class="col-span-4 relative min-h-[100px]"
      >
        <div id="player-hand" class="fixed bottom-0 w-full max-h-max" phx-hook="LayoutHand">
          <.card :for={card <- @game_player.hand_cards} id={card.id} card={card.card} />
        </div>
      </div>
    </div>
    """
  end

  def menu_dropdown(assigns) do
    ~H"""
    <div class="dropdown">
      <div
        tabindex="0"
        role="button"
        class="btn btn-ghost btn-secondary font-elektra font-bold font-lg"
      >
        Menu
      </div>
      <ul
        tabindex="0"
        class="dropdown-content menu bg-gray-900 rounded-box z-1 w-52 p-2 shadow-sm"
      >
        <li class="hover:text-orange-400">
          <a data-confirm="Are you sure? This will reset the game." phx-click="show-player-form">
            Change Deck
          </a>
        </li>
      </ul>
    </div>
    """
  end

  attr :deck_cards, :list, required: true

  def deck(assigns) do
    ~H"""
    <div class="relative group flex flex-col" tabindex="0">
      <.player_back :if={!Enum.empty?(@deck_cards)} id="player-deck" />
      <div class="absolute bottom-3 opacity-50 left-0 flex flex-row justify-center w-full">
        <div><span>{Enum.count(@deck_cards)}</span></div>
      </div>

      <div class="absolute hidden group-hover:flex group-focus:flex flex-col gap-1 left-full top-0 px-2">
        <.button variant="icon" phx-click="draw-1"><.icon name="hero-arrow-up-on-square" /></.button>
        <.button variant="icon" phx-click="draw-hand">
          <.icon name="hero-arrow-up-on-square-stack" />
        </.button>
      </div>
    </div>
    """
  end

  def identity(assigns) do
    ~H"""
    <div :if={@game_player.deck} class="relative group flex flex-col" tabindex="0">
      <% card =
        if @game_player.form == :hero, do: @game_player.deck.hero, else: @game_player.deck.alter_ego %>
      <.card id={card.id} card={card} />
      <div class="absolute hidden group-hover:flex group-focus:flex flex-col gap-1 left-full top-0 px-2">
        <.button variant="icon" phx-click="flip-hero"><.icon name="hero-arrow-uturn-left" /></.button>
      </div>
    </div>
    """
  end
end
