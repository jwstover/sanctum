defmodule SanctumWeb.GameLive.Index do
  @moduledoc false

  use SanctumWeb, :live_view

  on_mount {SanctumWeb.LiveUserAuth, :live_user_optional}

  alias Sanctum.Games

  def mount(_params, _session, socket) do
    {:ok, socket |> assign_games()}
  end

  def handle_event("new-game", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/games/new")}
  end

  def assign_games(socket) do
    {:ok, games} =
      Games.list_games(socket.assigns.current_user.id,
        query: [sort: [inserted_at: :desc]],
        load: [game_villian: [:card]],
        actor: socket.assigns.current_user
      )

    assign(socket, :games, games)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash}>
      <.button :if={@current_user} variant="primary" phx-click="new-game">New Game</.button>

      <div class="flex flex-col gap-2 mt-2 font-elektra">
        <div
          :for={game <- @games}
          class="px-4 py-2 border-b-4 border-t-2 border-l-1 border-r-4 border-black rounded skew-x-6 grid grid-cols-3 gap-4 items-center"
        >
          <span class="font-komika">
            {game.game_villian.card.name}
          </span>

          <span class="text-sm">{Calendar.strftime(game.inserted_at, "%a %b %d %H:%M %p")}</span>

          <div class="flex flex-row justify-end gap-2">
            <button class="btn btn-ghost btn-circle">
              <.icon name="hero-trash" class="size-6 text-red-600" />
            </button>
            <button class="btn btn-ghost btn-circle">
              <.link navigate={~p"/games/#{game.id}"}>
                <.icon name="hero-arrow-right-on-rectangle" class="size-6 text-green-600" />
              </.link>
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
