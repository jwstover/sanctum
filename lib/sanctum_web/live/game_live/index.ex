defmodule SanctumWeb.GameLive.Index do
  @moduledoc false

  use SanctumWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_event("new-game", _params, socket) do
    rhino_villian = Sanctum.Games.get_card_by_code!("01094")
    main_schema = Sanctum.Games.get_card_by_code!("01097")
    hero = Sanctum.Games.get_card_by_code!("01001a")

    game =
      Sanctum.Games.create_game!(%{
        villian_id: rhino_villian.id,
        main_scheme_id: main_schema.id,
        hero_id: hero.id
      })

    {:noreply, push_navigate(socket, to: ~p"/games/#{game.id}")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.button variant="primary" phx-click="new-game">New Game</.button>
    </Layouts.app>
    """
  end
end
