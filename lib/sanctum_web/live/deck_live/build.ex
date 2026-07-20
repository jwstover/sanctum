defmodule SanctumWeb.DeckLive.Build do
  @moduledoc """
  The native deckbuilder: a mobile-first card grid with tap-to-add steppers
  and a persistent deck panel. Only the owner of a native deck can build.
  """

  use SanctumWeb, :live_view

  alias Sanctum.Decks

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    case Decks.get_deck(id, actor: user, load: [hero: [:display_name]]) do
      {:ok, %{source: :native, owner_id: owner_id} = deck} when owner_id == user.id ->
        {:ok,
         socket
         |> assign(:page_title, "Build · #{deck.title}")
         |> assign(:deck, deck)}

      {:ok, deck} ->
        {:ok,
         socket
         |> put_flash(:error, "Only the owner can build this deck.")
         |> push_navigate(to: ~p"/decks/#{deck.id}")}

      {:error, _error} ->
        {:ok,
         socket
         |> put_flash(:error, "Deck not found.")
         |> push_navigate(to: ~p"/decks")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:decks}>
      <.header>
        {@deck.title}
        <:subtitle>{@deck.hero.display_name}</:subtitle>
      </.header>
      <p class="font-barlow-condensed text-base-content/60">
        The builder lands here next.
      </p>
    </Layouts.app>
    """
  end
end
