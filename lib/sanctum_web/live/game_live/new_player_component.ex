defmodule SanctumWeb.GameLive.NewPlayerComponent do
  @moduledoc false

  use SanctumWeb, :live_component

  alias Sanctum.Decks
  alias Sanctum.Decks.Deck
  alias Sanctum.Games
  alias Sanctum.MarvelCdb

  def update(assigns, socket) do
    {:ok,
     assign(socket, assigns)
     |> assign_mcdb_form()
     |> assign_form()
     |> assign_decks()}
  end

  def handle_event("import-deck", %{"deck_url" => deck_url}, socket) do
    case MarvelCdb.load_deck(deck_url) do
      {:ok, %Deck{} = deck} ->
        {:noreply, put_flash(socket, :info, "Imported deck #{deck.title}") |> assign_decks()}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to import deck")}
    end
  end

  def handle_event("select-deck", %{"form" => params}, socket) do
    game_player = socket.assigns.game_player
    current_user = socket.assigns.current_user

    case Games.select_deck(game_player, params, actor: current_user, load: [deck: [:hero]]) do
      {:ok, game_player} ->
        send(self(), {:deck_selected, game_player})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp assign_decks(socket) do
    case Decks.list_decks() do
      {:ok, decks} when is_list(decks) ->
        assign(socket, :decks, decks |> Enum.map(&{&1.title, &1.id}))

      _ ->
        socket
        |> assign(:decks, [])
        |> put_flash(:error, "Failed to load decks")
    end
  end

  defp assign_mcdb_form(socket) do
    assign(socket, :mcdb_form, to_form(%{}))
  end

  defp assign_form(%{assigns: %{game_player: game_player}} = socket)
       when not is_nil(game_player) do
    form = Games.form_to_select_deck(game_player) |> to_form()

    assign(socket, :form, form)
  end

  def render(assigns) do
    ~H"""
    <div>
      <dialog id="my_modal_1" class="modal modal-open !bg-black/80 ">
        <div class="text-center space-y-8 modal-box bg-transparent">
          <h3 class="text-2xl font-bold font-komika">Choose a Deck</h3>
          <.form for={@mcdb_form} phx-submit="import-deck" phx-target={@myself}>
            <div class="flex items-end w-full gap-2">
              <div class="flex-1">
                <.input
                  placeholder="MarvelCDB Deck Link"
                  value=""
                  name="deck_url"
                  class="w-full input rounded text-base-content"
                />
              </div>
              <div>
                <.button type="submit">Import</.button>
              </div>
            </div>
          </.form>

          <.form for={@form} phx-submit="select-deck" class="space-y-2" phx-target={@myself}>
            <.input
              type="select"
              prompt="Select a Deck"
              field={@form[:deck_id]}
              options={@decks}
              class="w-full input rounded text-base-content"
            />
            <div>
              <.button type="submit">Select</.button>
            </div>
          </.form>
        </div>
      </dialog>
    </div>
    """
  end
end
