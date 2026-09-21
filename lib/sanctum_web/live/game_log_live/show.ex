defmodule SanctumWeb.GameLogLive.Show do
  @moduledoc false

  use SanctumWeb, :live_view

  alias Sanctum.GameLog

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    case GameLog.get_logged_game(id,
           actor: user,
           load: [
             :scenario,
             :villain,
             main_scheme: [:primary_side],
             logged_game_players: [hero: [:display_name], aspect_def: [:label, :color]]
           ]
         ) do
      {:ok, game} ->
        {:ok, socket |> assign(:page_title, "Logged Game") |> assign(:game, game)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Game not found")
         |> push_navigate(to: ~p"/game-log")}
    end
  end

  def handle_event("delete", _params, socket) do
    user = socket.assigns.current_user
    :ok = GameLog.destroy_logged_game(socket.assigns.game, actor: user)

    {:noreply,
     socket
     |> put_flash(:info, "Game deleted")
     |> push_navigate(to: ~p"/game-log")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:game_log}>
      <.header>
        {@game.villain.villain_name}
        <:actions>
          <.button variant="ghost" navigate={~p"/game-log"}>Back</.button>
          <.confirm_button
            id="confirm-delete-game"
            message="Delete this logged game? This cannot be undone."
            confirm_label="Delete game"
            class="btn btn-error"
            phx-click="delete"
          >
            <.icon name="hero-trash" class="size-4" /> Delete
          </.confirm_button>
        </:actions>
      </.header>

      <p class="mb-4 font-barlow-condensed uppercase tracking-[0.08em] text-base-content/60">
        {@game.scenario.name} &middot; {Calendar.strftime(@game.played_at, "%B %-d, %Y")}
      </p>

      <div class="grid max-w-2xl gap-4">
        <.panel class="p-4">
          <h2 class="mb-2 font-barlow-condensed text-lg uppercase tracking-[0.08em]">Players</h2>
          <ul class="space-y-2">
            <li :for={player <- @game.logged_game_players} class="flex items-center gap-3">
              <span class="font-anton text-lg uppercase">{player.hero.display_name}</span>
              <span
                :if={player.aspect_def}
                class="border-2 border-neutral px-2 py-0.5 font-barlow-condensed text-xs font-bold uppercase tracking-[0.1em] text-neutral"
                style={"background-color: #{player.aspect_def.color}"}
              >
                {player.aspect_def.label}
              </span>
              <span :if={!player.aspect_def} class="text-sm text-base-content/50">No aspect</span>
            </li>
          </ul>
        </.panel>

        <.panel :if={@game.main_scheme} class="p-4">
          <h2 class="mb-2 font-barlow-condensed text-lg uppercase tracking-[0.08em]">Main scheme</h2>
          <p class="font-barlow">{@game.main_scheme.primary_side.name}</p>
        </.panel>

        <.panel class="p-4">
          <h2 class="mb-2 font-barlow-condensed text-lg uppercase tracking-[0.08em]">
            Modular sets
          </h2>
          <p :if={@game.modular_sets == []} class="text-base-content/50">None</p>
          <div class="flex flex-wrap gap-1">
            <span
              :for={code <- @game.modular_sets}
              class="border-2 border-neutral bg-base-300 px-2 py-0.5 font-ibm-mono text-xs"
            >
              {code}
            </span>
          </div>
        </.panel>
      </div>
    </Layouts.app>
    """
  end
end
