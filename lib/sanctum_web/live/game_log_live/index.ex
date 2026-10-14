defmodule SanctumWeb.GameLogLive.Index do
  @moduledoc false

  use SanctumWeb, :live_view

  alias Sanctum.GameLog

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Game Log")
     |> assign_games()}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    game = GameLog.get_logged_game!(id, actor: user)
    :ok = GameLog.destroy_logged_game(game, actor: user)

    {:noreply, socket |> put_flash(:info, "Game deleted") |> assign_games()}
  end

  defp assign_games(socket) do
    user = socket.assigns.current_user

    games =
      GameLog.list_logged_games!(
        actor: user,
        load: [:scenario, :villain, logged_game_players: [hero: [:display_name]]]
      )

    assign(socket, :games, games)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:game_log}>
      <.header>
        Game Log
        <:actions>
          <.button variant="primary" navigate={~p"/game-log/new"}>
            <.icon name="hero-plus" /> Log a Game
          </.button>
        </:actions>
      </.header>

      <p class="mb-6 max-w-2xl font-barlow text-base-content/70">
        A record of the physical games you've played: the villain, modular sets, and each
        player's hero and aspect.
      </p>

      <div
        :if={@games == []}
        class="border-2 border-dashed border-neutral bg-base-200 p-8 text-center"
      >
        <p class="font-barlow-condensed text-lg uppercase tracking-[0.08em] text-base-content/60">
          No games logged yet
        </p>
        <p class="mt-1 font-barlow text-base-content/50">
          Log your first tabletop game to start your history.
        </p>
      </div>

      <div :if={@games != []} class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <.panel :for={game <- @games} class="flex flex-col gap-3 p-4">
          <div>
            <h2 class="font-anton text-xl uppercase leading-none">{game.villain.villain_name}</h2>
            <p class="mt-1 font-barlow-condensed text-sm uppercase tracking-[0.08em] text-base-content/60">
              {game.scenario.name} &middot; {Calendar.strftime(game.played_at, "%b %-d, %Y")}
            </p>
          </div>

          <div class="flex flex-wrap gap-1">
            <span
              :for={player <- game.logged_game_players}
              class="border-2 border-neutral bg-base-300 px-2 py-0.5 font-barlow-condensed text-xs font-bold uppercase tracking-[0.1em]"
            >
              {player.hero.display_name}
            </span>
          </div>

          <div class="mt-auto flex gap-2">
            <.button variant="ghost" navigate={~p"/game-log/#{game.id}"} class="flex-1">
              View
            </.button>
            <.button
              variant="icon"
              phx-click={open_confirm("confirm-delete-#{game.id}")}
              aria-label="Delete game"
            >
              <.icon name="hero-trash" class="size-4" />
            </.button>
            <.confirm_dialog
              id={"confirm-delete-#{game.id}"}
              message="Delete this logged game? This cannot be undone."
              confirm_label="Delete game"
              phx-click="delete"
              phx-value-id={game.id}
            />
          </div>
        </.panel>
      </div>
    </Layouts.app>
    """
  end
end
