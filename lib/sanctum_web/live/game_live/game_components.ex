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
      <div class="pointer-events-none fixed left-2 bottom-2 hidden peer-hover:not-peer-[.game-card-dragging]:block z-1000 p-3 bg-black ">
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

  attr :id, :string
  attr :size, :string, default: "w-9 h-9"
  attr :value, :integer, required: true

  def threat_token(assigns) do
    ~H"""
    <div id={@id} class={[@size, "relative"]}>
      <svg
        class={[@size]}
        viewBox="0 0 119.93881 102.72617"
        version="1.1"
        xmlns="http://www.w3.org/2000/svg"
        xmlns:svg="http://www.w3.org/2000/svg"
      >
        <g transform="translate(-0.04515646,-10.493607)">
          <path
            style="fill-opacity:1;stroke:#000000;stroke-width:5.2722;stroke-dasharray:none;stroke-opacity:1"
            class="fill-yellow-500"
            d="M 44.437747,33.669157 71.339938,81.147582 A 8.3844013,8.3844013 120.46327 0 1 63.977383,93.665063 L 6.7897997,93.202655 A 7.6982014,7.6982014 60.463272 0 1 0.21654583,81.601826 L 28.485541,33.540171 a 9.2103112,9.2103112 0.46327229 0 1 15.952206,0.128986 z"
            transform="matrix(1.5280274,-0.01058529,0.01408293,1.474719,4.120711,-28.120265)"
          />
        </g>
      </svg>
      <div class="absolute top-[3px] left-0 w-full h-full grid place-items-center">
        <span class="font-lg font-komika text-bold text-white text-shadow-[0_0_2px_black,0_0_2px_black,0_0_2px_black,0_0_2px_black]">
          {@value}
        </span>
      </div>
    </div>
    """
  end

  def damage_token(assigns) do
    ~H"""
    <div class="relative w-8 h-8 rounded-full grid place-items-center bg-red-700 border-4 border-black">
      <span class="font-lg font-komika text-bold text-white text-shadow-[0_0_2px_black,0_0_2px_black,0_0_2px_black,0_0_2px_black]">
        {@value}
      </span>
    </div>
    """
  end

  def counter_token(assigns) do
    ~H"""
    <div class="relative w-8 h-8 grid place-items-center rounded-lg bg-emerald-500 border-4 border-black">
      <span class="font-lg font-komika text-bold text-white text-shadow-[0_0_2px_black,0_0_2px_black,0_0_2px_black,0_0_2px_black]">
        {@value}
      </span>
    </div>
    """
  end
end
