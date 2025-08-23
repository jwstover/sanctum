defmodule SanctumWeb.GameLive.New do
  @moduledoc false

  use SanctumWeb, :live_view

  alias Sanctum.Games

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_scenarios()
     |> assign_form()}
  end

  def handle_event("create", %{"form" => game_params}, socket) do
    current_user = socket.assigns.current_user

    case Games.create_game(game_params, actor: current_user) do
      {:ok, game} ->
        {:noreply, push_navigate(socket, to: ~p"/games/#{game.id}")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> put_flash(:error, "Failed to create game")}
    end
  end

  defp assign_scenarios(socket) do
    {:ok, scenarios} = Games.list_scenarios()

    assign(socket, :scenarios, Enum.map(scenarios, &{&1.name, &1.id}))
  end

  defp assign_form(socket) do
    form = Games.form_to_create_game() |> to_form()
    assign(socket, :form, form)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash}>
      <.header>New Game</.header>

      <.form for={@form} phx-submit="create">
        <.input
          type="select"
          field={@form[:scenario_id]}
          label="Scenario"
          prompt="Choose a Scenario"
          options={@scenarios}
        />

        <div class="mt-2">
          <.button phx-disable-with="Creating..." variant="primary" type="submit">
            Create Game
          </.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
