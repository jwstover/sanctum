defmodule SanctumWeb.GuessLive.Play do
  @moduledoc """
  "Flavor Town" — a flavor-text guessing game inspired by the *Stunned &
  Confused* podcast segment. The player is shown a card's flavor text and tries
  to name it. Each wrong guess reveals the next narrowing hint; once the hints
  run out, the next wrong guess ends the round and reveals the card.

  The round itself lives in `SanctumWeb.GuessLive.GameComponent` (shared with
  the homepage embed); this page is the full-screen shell around it.
  """
  use SanctumWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:guess}>
      <.header>
        Flavor Town
      </.header>

      <.live_component module={SanctumWeb.GuessLive.GameComponent} id="flavor-game" mode={:full} />
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Flavor Town")}
  end
end
