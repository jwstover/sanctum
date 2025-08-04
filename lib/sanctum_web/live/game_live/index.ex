defmodule SanctumWeb.GameLive.Index do
  @moduledoc false

  use SanctumWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_event("new-game", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/games/new")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.button variant="primary" phx-click="new-game">New Game</.button>
    </Layouts.app>
    """
  end
end
