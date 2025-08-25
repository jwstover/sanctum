defmodule SanctumWeb.GameLive.GameComponents do
  @moduledoc false

  use SanctumWeb, :html

  @landscape_types [
    :main_scheme
  ]

  attr :id, :string, required: true
  attr :card, Sanctum.Games.Card, default: nil
  attr :game_card_id, :string, default: nil
  attr :imgsrc, :string, default: nil
  attr :zone, :string, default: nil

  def card(assigns) do
    assigns =
      assign(assigns, :src, assigns.imgsrc || assigns.card.image_url)
      |> assign(
        :aspect,
        if assigns.card && assigns.card.type in @landscape_types do
          "max-h-[71px] lg:max-h-[110px]"
        else
          "max-h-[100px] lg:max-h-[153px]"
        end
      )

    ~H"""
    <div id={@id}>
      <div
        id={@id <> "-drag"}
        class={[
          "game-card max-w-fit peer relative p-1 bg-black border border-gray-700 shadow shadow-black"
        ]}
        phx-hook="CardDrag"
        data-game_card_id={@game_card_id}
        data-zone={@zone}
      >
        <figure class="rounded-[4.5%] overflow-hidden">
          <img class={[@aspect, "object-fit"]} src={@src} />
        </figure>
        <div class="absolute top-0 left-0 w-full h-full touch-none" />
      </div>
      <div class="fixed left-2 bottom-2 hidden peer-hover:not-peer-[.game-card-dragging]:block z-1000 p-4 bg-black ">
        <figure class="rounded-[4.5%] overflow-hidden">
          <img class={["h-[30vh] object-fit"]} src={@src} />
        </figure>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true

  def encounter_back(assigns) do
    ~H"""
    <.card id={@id} imgsrc={~p"/images/encounter-back.webp"} />
    """
  end

  attr :id, :string, required: true

  def player_back(assigns) do
    ~H"""
    <.card id={@id} imgsrc={~p"/images/player-back.webp"} />
    """
  end
end
