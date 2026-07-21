defmodule SanctumWeb.GameLive.Index do
  @moduledoc false

  use SanctumWeb, :live_view

  on_mount {SanctumWeb.LiveUserAuth, :live_user_optional}

  alias Sanctum.Games
  alias SanctumWeb.Timezone

  def mount(_params, _session, socket) do
    # nil until loaded — drives the loading skeleton. Anonymous visitors have no
    # games and need no query, so they resolve to an empty list immediately.
    socket = socket |> assign(:page_title, "Games") |> assign(:games, nil)

    socket =
      cond do
        is_nil(socket.assigns.current_user) ->
          assign(socket, :games, [])

        # Skip the query on the static render; load asynchronously once connected.
        connected?(socket) ->
          user = socket.assigns.current_user
          start_async(socket, :load_games, fn -> load_games(user) end)

        true ->
          socket
      end

    {:ok, socket}
  end

  def handle_event("new-game", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/games/new")}
  end

  def handle_async(:load_games, {:ok, games}, socket) do
    {:noreply, assign(socket, :games, games)}
  end

  def handle_async(:load_games, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:games, [])
     |> put_flash(:error, "Couldn’t load games: #{inspect(reason)}")}
  end

  defp load_games(user) do
    {:ok, games} =
      Games.list_games(user.id,
        query: [sort: [inserted_at: :desc]],
        load: [game_villain: [:villain]],
        actor: user
      )

    games
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:games}>
      <.button :if={@current_user} variant="primary" phx-click="new-game">New Game</.button>

      <div :if={@games == nil} class="mt-2 flex flex-col gap-2">
        <div
          :for={_ <- 1..3}
          class="h-12 animate-pulse rounded border-b-4 border-l-1 border-r-4 border-t-2 border-black bg-base-300"
        >
        </div>
      </div>

      <div class="flex flex-col gap-2 mt-2 font-elektra">
        <div
          :for={game <- @games || []}
          :if={game.game_villain}
          class="px-4 py-2 border-b-4 border-t-2 border-l-1 border-r-4 border-black rounded skew-x-6 grid grid-cols-3 gap-4 items-center"
        >
          <span class="font-komika">
            {game.game_villain.villain.villain_name}
          </span>

          <span class="text-sm">
            {game.inserted_at
            |> Timezone.to_local(@timezone)
            |> Calendar.strftime("%a %b %-d %I:%M %p")}
          </span>

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
