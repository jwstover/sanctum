defmodule SanctumWeb.GameLive.GameComponents do
  @moduledoc false

  use SanctumWeb, :html

  @landscape_types [
    :main_scheme
  ]

  attr :id, :string, required: true
  attr :card, Sanctum.Games.Card, default: nil
  attr :imgsrc, :string, default: nil

  def card(assigns) do
    assigns =
      assign(assigns, :src, assigns.imgsrc || assigns.card.image_url)
      |> assign(
        :aspect,
        if assigns.card && assigns.card.type in @landscape_types do
          "max-h-[71px] lg:h-[110px]"
        else
          "max-h-[100px] lg:h-[153px]"
        end
      )

    ~H"""
    <div
      id={@id}
      class={["game-card max-w-fit relative p-1 bg-black border border-gray-700 shadow shadow-black"]}
      phx-hook="CardDrag"
    >
      <figure class="rounded-[4.5%] overflow-hidden">
        <img class={[@aspect, "object-fit"]} src={@src} />
      </figure>
      <div class="absolute top-0 left-0 w-full h-full touch-none" />
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
