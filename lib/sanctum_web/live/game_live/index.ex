defmodule SanctumWeb.GameLive.Index do
  @moduledoc false

  use SanctumWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="font-metropolis font-bold">Bold Metropolis heading</h1>
      <p class="font-exo2 font-light">Light Exo2 text</p>
      <div class="font-komika">Comic-style Komika text</div>
      <span class="font-elektra">Elektra Medium Pro text</span>
    </Layouts.app>
    """
  end
end
