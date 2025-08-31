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
     |> stream(:facedown_encounters, [])
     |> stream(:hero_play_cards, [])
     |> stream(:hand_cards, [])
     |> assign_game()
     |> assign_game_player()
     |> stream_facedown_encounters()
     |> stream_hero_play_cards()
     |> stream_hand_cards()
     |> stream_main_schemes()
     |> assign_hero_discard()
     |> assign_encounter_discard()}
  end

  defp stream_facedown_encounters(socket) do
    game_player_id = socket.assigns.game_player.id

    facedown_encounter_cards =
      socket.assigns.game.encounter_deck.facedown_encounter_cards
      |> Enum.filter(&(&1.game_player_id == game_player_id))

    stream(socket, :facedown_encounters, facedown_encounter_cards, reset: true)
  end

  defp stream_hero_play_cards(socket) do
    hero_play_cards = socket.assigns.game_player.hero_play_cards

    stream(socket, :hero_play_cards, hero_play_cards, reset: true)
  end

  defp stream_hand_cards(socket) do
    hand_cards = socket.assigns.game_player.hand_cards

    stream(socket, :hand_cards, hand_cards, reset: true)
  end

  defp stream_main_schemes(socket) do
    main_schemes = socket.assigns.game.game_schemes

    stream(socket, :main_schemes, main_schemes, reset: true)
  end

  def handle_info({:deck_selected, _game_player}, socket) do
    {:noreply,
     socket
     |> assign_game_player()
     |> assign(:show_player_form, false)}
  end

  def handle_event(
        "card-dropped",
        %{"card" => game_card_id, "zone" => zone_name} = params,
        socket
      ) do
    source_zone = Map.get(params, "source_zone")
    user = socket.assigns.current_user
    game_card = Games.get_game_card!(game_card_id, actor: user)

    {:ok, updated_card} =
      Games.move_game_card(game_card, %{zone: zone_name}, load: [:card], actor: user)

    # Remove from source stream
    socket =
      case source_zone do
        "hero_play" ->
          stream_delete(socket, :hero_play_cards, game_card)

        "hero_hand" ->
          stream_delete(socket, :hand_cards, game_card)

        "facedown_encounter" ->
          stream_delete(socket, :facedown_encounters, game_card)

        "hero_discard" ->
          assign(socket, :hero_discard, Enum.drop(socket.assigns.hero_discard, 1))

        "encounter_discard" ->
          assign(socket, :encounter_discard, Enum.drop(socket.assigns.hero_discard, 1))

        _ ->
          socket
      end

    # Add to destination stream  
    socket =
      case zone_name do
        "hero_play" ->
          stream_insert(socket, :hero_play_cards, updated_card)

        "hero_hand" ->
          stream_insert(socket, :hand_cards, updated_card)

        "hero_discard" ->
          assign(socket, :hero_discard, [updated_card | socket.assigns.hero_discard])

        "encounter_discard" ->
          assign(socket, :encounter_discard, [updated_card | socket.assigns.encounter_discard])

        _ ->
          socket
      end

    {:noreply, socket}
  end

  def handle_event("show-player-form", _params, socket) do
    {:noreply, assign(socket, :show_player_form, true)}
  end

  def handle_event("deal-encounter", params, socket) do
    count = Map.get(params, "count", 1)

    game_encounter_deck_id = socket.assigns.game.encounter_deck.id
    game_player_id = socket.assigns.game_player.id

    cards =
      Games.deal_facedown_encounter_cards(game_encounter_deck_id, count, game_player_id,
        actor: socket.assigns.current_user
      )

    {:noreply, stream(socket, :facedown_encounters, cards)}
  end

  def handle_event("draw-1", _params, socket) do
    game_player = socket.assigns.game_player

    Games.draw_cards(game_player.id, 1, game_player.current_hand_size,
      actor: socket.assigns.current_user
    )

    {:noreply, socket |> assign_game_player() |> stream_hand_cards()}
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

    {:noreply, socket |> assign_game_player() |> stream_hand_cards()}
  end

  def handle_event("flip-hero", _params, socket) do
    game_player = socket.assigns.game_player

    Games.flip_identity(game_player)

    {:noreply, socket |> assign_game_player()}
  end

  def handle_event("change-health", %{"amount" => amount_str}, socket) do
    game_player = socket.assigns.game_player
    amount = String.to_integer(amount_str)

    Games.change_health(game_player, %{amount: amount}, actor: socket.assigns.current_user)

    {:noreply, socket |> assign_game_player()}
  end

  def handle_event("change-villain-health", %{"amount" => amount_str}, socket) do
    game_villain = socket.assigns.game.game_villian
    amount = String.to_integer(amount_str)

    Games.change_villain_health(game_villain, %{amount: amount},
      actor: socket.assigns.current_user
    )

    {:noreply, socket |> assign_game()}
  end

  def handle_event("flip", %{"game_card_id" => game_card_id}, socket) do
    {:ok, card} =
      Games.get_game_card!(game_card_id, load: [:card], actor: socket.assigns.current_user)
      |> Games.flip_card()

    zone =
      case card.zone do
        :hero_hand -> :hand_cards
        :hero_play -> :hero_play_cards
        :facedown_encounter -> :facedown_encounters
      end

    {:noreply, stream_insert(socket, zone, card)}
  end

  def handle_event(
        "update-counter",
        %{
          "game_card_id" => game_card_id,
          "counter_type" => counter_type,
          "delta" => delta_str
        },
        socket
      ) do
    delta = String.to_integer(delta_str)

    # Build arguments based on counter type
    args =
      case counter_type do
        "threat" -> %{threat_delta: delta}
        "damage" -> %{damage_delta: delta}
        "counter" -> %{counter_delta: delta}
      end

    card = Games.get_game_card!(game_card_id, load: [:card], actor: socket.assigns.current_user)

    card =
      card
      |> Ash.Changeset.for_update(:update_counters, args)
      |> Ash.update!(actor: socket.assigns.current_user)

    zone =
      case card.zone do
        :hero_hand -> :hand_cards
        :hero_play -> :hero_play_cards
        :facedown_encounter -> :facedown_encounters
      end

    {:noreply, stream_insert(socket, zone, card)}
  end

  def handle_event(
        "update-scheme-threat",
        %{"delta" => delta, "game_scheme_id" => game_scheme_id},
        socket
      ) do
    game_scheme = Games.get_game_scheme!(game_scheme_id, actor: socket.assigns.current_user)

    Games.update_scheme_threat(game_scheme, delta, load: [:card], actor: socket.assigns.current_user)
    |> case do
      {:ok, scheme} -> stream_insert(socket, :main_schemes, scheme)
      _ -> socket
    end
    |> then(&{:noreply, &1})
  end

  def handle_event(
        "update-scheme-counter",
        %{"delta" => delta, "game_scheme_id" => game_scheme_id},
        socket
      ) do
    game_scheme = Games.get_game_scheme!(game_scheme_id, actor: socket.assigns.current_user)

    Games.update_scheme_counter(game_scheme, delta, load: [:card], actor: socket.assigns.current_user)
    |> case do
      {:ok, scheme} -> stream_insert(socket, :main_schemes, scheme)
      _ -> socket
    end
    |> then(&{:noreply, &1})
  end

  @spec assign_game(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_game(%{assigns: %{game_id: game_id, current_user: current_user}} = socket)
       when is_binary(game_id) do
    case Games.get_game(game_id,
           load: [
             game_villian: [:card],
             game_schemes: [:card],
             encounter_deck: [
               deck_cards: [:card],
               facedown_encounter_cards: [:card],
               discard_cards: [:card]
             ]
           ],
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
          hero_discard: [:card],
          deck: [:hero, :alter_ego]
        ],
        actor: socket.assigns.current_user
      )
    )
  end

  defp assign_hero_discard(socket) do
    game_player = socket.assigns.game_player

    assign(socket, :hero_discard, game_player.hero_discard |> Enum.reverse())
  end

  defp assign_encounter_discard(socket) do
    encounter_discard = socket.assigns.game.encounter_deck.discard_cards |> Enum.reverse()

    assign(socket, :encounter_discard, encounter_discard)
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
      <.play_area
        game={@game}
        game_player={@game_player}
        streams={@streams}
        hero_discard={@hero_discard}
        encounter_discard={@encounter_discard}
      />
    </Layouts.game>
    """
  end

  attr :streams, :any, required: true
  attr :game, Game, required: true
  attr :game_player, GamePlayer, required: true
  attr :hero_discard, :list, required: true
  attr :encounter_discard, :list, required: true

  def play_area(assigns) do
    ~H"""
    <div
      id="game-board"
      class="h-full overflow-x-hidden overflow-y-auto grid grid-rows-[auto_repeat(5,1fr)] grid-cols-4 gap-4"
    >
      <div class="col-span-4 bg-gray-900 p-2 flex flex-row items-center justify-between">
        <.menu_dropdown />

        <div class="flex flex-row items-center">
          <button
            class="cursor-pointer py-1 px-2 text-lg w-8"
            phx-click="change-villain-health"
            phx-value-amount="-1"
          >
            <span class="text-white font-komika">-</span>
          </button>
          <div class="flex flex-col items-center bg-red-800 text-white transition-all font-komika text-lg py-1 px-4 border-y-1 -skew-x-6 border-x-2 border-gray-100 shadow shadow-black">
            {@game.game_villian.health}
            <span class="text-xs font-elektra">Villian</span>
          </div>
          <button
            class="cursor-pointer p-1 px-2 text-lg w-8"
            phx-click="change-villain-health"
            phx-value-amount="1"
          >
            <span class="text-white font-komika">+</span>
          </button>
        </div>

        <div class="flex flex-row items-center">
          <button
            class="cursor-pointer py-1 px-2 text-lg w-8"
            phx-click="change-health"
            phx-value-amount="-1"
          >
            <span class="text-white font-komika">-</span>
          </button>
          <div class="flex flex-col items-center bg-green-800 text-white transition-all font-komika text-lg py-1 px-4 border-y-1 -skew-x-6 border-x-2 border-gray-100 shadow shadow-black">
            {@game_player.health}
            <span class="text-xs font-elektra">Hero</span>
          </div>
          <button
            class="cursor-pointer p-1 px-2 text-lg w-8"
            phx-click="change-health"
            phx-value-amount="1"
          >
            <span class="text-white font-komika">+</span>
          </button>
        </div>
      </div>
      <div
        id="main-schema-area"
        class="flex flex-col items-center justify-center bg-blue-300/5 rounded border-4 border-gray-100/10"
        phx-update="stream"
      >
        <.scheme_card
          :for={{dom_id, main_scheme} <- @streams.main_schemes}
          id={dom_id}
          game_scheme={main_scheme}
        />
      </div>
      <div
        id="villian-area"
        class="flex flex-row items-center justify-center bg-blue-300/5 rounded border-4 border-gray-100/10"
      >
        <.plain_card
          id={@game.game_villian.card.id}
          card={@game.game_villian.card}
        />
      </div>
      <div
        id="encounter-deck-area"
        class="flex flex-row items-center justify-center bg-blue-300/5 rounded border-4 border-gray-100/10"
      >
        <.encounter_deck encounter_deck={@game.encounter_deck} />
      </div>
      <div
        id="encounter-discard-area"
        class="flex flex-row items-center justify-center bg-blue-300/5 rounded border-4 border-gray-100/10"
        phx-hook="DragDrop"
        data-drop_zone="encounter_discard"
      >
        <.card
          :if={!Enum.empty?(@encounter_discard)}
          id="encounter-discard-pile"
          game_card={hd(@encounter_discard)}
          show_tokens={false}
          zone="encounter_discard"
        />
      </div>
      <div
        id="encounter-area"
        class="col-span-4 relative flex flex-row items-center justify-center bg-blue-300/5 rounded border-4 border-gray-100/10"
      >
        <div class="absolute top-0 left-0 w-full h-full flex items-center justify-center text-3xl font-komika opacity-50">
          Encounter Area
        </div>

        <div
          id="facedown-encounters"
          class="flex flex-row flex-wrap gap-1 items-center justify-center"
          phx-update="stream"
        >
          <%= for {dom_id, card} <- @streams.facedown_encounters do %>
            <div id={dom_id} class="relative group" tabindex="0">
              <div class="relative">
                <.card
                  :if={card.face_up}
                  id={card.id}
                  game_card={card}
                  zone="facedown_encounter"
                />
                <.encounter_back :if={!card.face_up} id={card.id} />
                <div class="absolute hidden group-hover:flex group-focus:flex w-full bottom-2 flex-col items-center">
                  <button
                    class="btn btn-sm bg-gray-900 text-gray-100 border-none rounded shadow shadow-gray-800 font-elektra"
                    phx-click="flip"
                    phx-value-game_card_id={card.id}
                  >
                    Flip
                  </button>
                </div>
              </div>
            </div>
          <% end %>
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
        <div
          id="player-area-cards"
          class="flex flex-row flex-wrap items-center justify-center"
          phx-update="stream"
        >
          <%= for {dom_id, card} <- @streams.hero_play_cards do %>
            <.card id={dom_id} game_card={card} zone="hero_play" />
          <% end %>
        </div>
      </div>

      <div
        id="player-side-schema-area"
        class="flex flex-row items-center justify-center bg-blue-300/5 rounded border-4 border-gray-100/10"
      >
      </div>

      <div
        id="hero-area"
        class="flex flex-row items-center justify-center bg-blue-300/5 rounded border-4 border-gray-100/10 z-20"
      >
        <.identity game_player={@game_player} />
      </div>
      <div
        id="player-deck-area"
        class="flex flex-row items-center justify-center bg-blue-300/5 rounded border-4 border-gray-100/10 z-10"
      >
        <.deck deck_cards={@game_player.deck_cards} />
      </div>
      <div
        id="hero-discard"
        class="flex flex-row items-center justify-center bg-blue-300/5 rounded border-4 border-gray-100/10"
        phx-hook="DragDrop"
        data-drop_zone="hero_discard"
      >
        <.card
          :if={!Enum.empty?(@hero_discard)}
          id="hero-discard-pile"
          game_card={hd(@hero_discard)}
          zone="hero_discard"
          show_tokens={false}
        />
      </div>

      <div
        id="player-hand-area"
        class="col-span-4 min-h-[100px] z-100"
      >
        <div
          id="player-hand"
          class="fixed bottom-0 w-full max-h-max"
          phx-hook="LayoutHand"
        >
          <div
            id="player-hand-dropzone"
            class="w-full h-full border-4 rounded border-transparent"
            phx-hook="DragDrop"
            phx-update="stream"
            data-drop_zone="hero_hand"
          >
            <%= for {dom_id, card} <- @streams.hand_cards do %>
              <.card id={dom_id} game_card={card} zone="hero_hand" show_tokens={false} />
            <% end %>
          </div>
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
        <li class="hover:text-orange-400">
          <a phx-click="reload">
            Reload
          </a>
        </li>
        <li>
          <.link navigate={~p"/"}>
            Leave Game
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  def encounter_deck(assigns) do
    ~H"""
    <div class="relative group" tabindex="0">
      <.encounter_back id="encounter-deck" />
      <ul class="absolute top-[100%] right-0 hidden group-hover:flex group-focus:flex menu dropdown-content bg-gray-900 rounded-box z-1 w-52 p-2 shadow-sm">
        <li phx-click="deal-encounter"><a>Deal Encounter</a></li>
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
      <.plain_card id={card.id} card={card} />
      <div class="absolute hidden group-hover:flex group-focus:flex flex-col gap-1 left-full top-0 px-2">
        <.button variant="icon" phx-click="flip-hero"><.icon name="hero-arrow-uturn-left" /></.button>
      </div>
    </div>
    """
  end

  def encounter_card(assigns) do
    ~H"""
    """
  end
end
