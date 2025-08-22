defmodule SanctumWeb.GameLive.GameComponents do
  @moduledoc false

  use SanctumWeb, :html

  @landscape_types [
    :main_scheme
  ]

  attr :card, Sanctum.Games.Card, default: nil
  attr :imgsrc, :string, default: nil

  def card(assigns) do
    assigns =
      assign(assigns, :src, assigns.imgsrc || assigns.card.image_url)
      |> assign(
        :aspect,
        if assigns.card && assigns.card.type in @landscape_types do
          "aspect-[calc(88/63)] h-[110px]"
        else
          "aspect-[calc(63/88)] h-[153px]"
        end
      )

    ~H"""
    <div class={[@aspect, "game-card max-h-full p-1 bg-black shadow shadow-black"]}>
      <figure class="rounded-[4.5%] overflow-hidden">
        <img class="object-fit" src={@src} />
      </figure>
    </div>
    """
  end

  def encounter_back(assigns) do
    ~H"""
    <.card imgsrc={~p"/images/encounter-back.webp"} />
    """
  end

  def player_back(assigns) do
    ~H"""
    <.card imgsrc={~p"/images/player-back.webp"} />
    """
  end
end
