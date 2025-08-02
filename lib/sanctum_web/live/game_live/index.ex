defmodule SanctumWeb.GameLive.Index do
  @moduledoc false

  use SanctumWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.button variant="primary">New Game</.button>
    </Layouts.app>
    """
  end
end
