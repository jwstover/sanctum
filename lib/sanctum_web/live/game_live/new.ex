defmodule SanctumWeb.GameLive.New do
  @moduledoc false

  use SanctumWeb, :live_view

  alias Sanctum.MarvelCdb
  alias Sanctum.Decks.Deck
  alias Sanctum.Decks
  alias Sanctum.Games

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_decks()
     |> assign_form()
     |> assign_mcdb_form()}
  end

  def handle_event("import-deck", %{"deck_url" => deck_url}, socket) do
    case MarvelCdb.load_deck(deck_url) do
      {:ok, %Deck{} = deck} ->
        {:noreply, put_flash(socket, :info, "Imported deck #{deck.title}") |> assign_decks()}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to import deck")}
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

  defp assign_form(socket) do
    form = Games.form_to_create_game() |> to_form()
    assign(socket, :form, form)
  end

  defp assign_mcdb_form(socket) do
    assign(socket, :mcdb_form, to_form(%{}))
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>New Game</.header>

      <.form for={@mcdb_form} phx-submit="import-deck">
        <div class="flex items-end w-full gap-2">
          <div class="flex-1">
            <.input label="MarvelCDB Deck Link" value="" name="deck_url" />
          </div>
          <div>
            <.button type="submit">Import</.button>
          </div>
        </div>
      </.form>

      <.form for={@form} phx-submit="create">
        <.input
          type="select"
          field={@form[:deck_id]}
          label="Deck"
          prompt="Choose a deck"
          options={@decks}
        />
      </.form>
    </Layouts.app>
    """
  end
end
