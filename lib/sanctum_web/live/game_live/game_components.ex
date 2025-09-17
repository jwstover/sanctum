defmodule SanctumWeb.GameLive.GameComponents do
  @moduledoc false

  use SanctumWeb, :html

  @landscape_types [
    :main_scheme
  ]

  def scheme_card(assigns) do
    ~H"""
    <div
      id={@id}
      class="relative group"
      tabindex="0"
      phx-click={JS.push("select-scheme", value: %{card_id: @game_scheme.id})}
    >
      <div class="absolute opacity-0 left-1/3 sm:group-hover:not-peer-[.game-card-dragging]:opacity-100 space-y-2 sm:group-focus:not-peer-[.game-card-dragging]:opacity-100 top-0 group-hover:left-[90%] group-focus:left-[90%] transition-all pt-[2px] pb-[4px] pl-[2px] pr-[4px]">
        <div class="h-full w-full p-1 pr-2 pl-7 ">
          <div class="grid grid-cols-[auto_auto] gap-1 items-center justify-center">
            <button
              class="cursor-pointer hover:scale-105 active:scale-95"
              phx-click="update-scheme-threat"
              phx-value-game_scheme_id={@game_scheme.id}
              phx-value-delta="-1"
            >
              <.threat_token value="-1" size="size-8" />
            </button>
            <button
              class="cursor-pointer hover:scale-105 active:scale-95"
              phx-click="update-scheme-threat"
              phx-value-game_scheme_id={@game_scheme.id}
              phx-value-delta="1"
            >
              <.threat_token value="+1" size="size-8" />
            </button>
            <button
              class="cursor-pointer hover:scale-105 active:scale-95"
              phx-click="update-scheme-counter"
              phx-value-game_scheme_id={@game_scheme.id}
              phx-value-delta="-1"
            >
              <.counter_token value="-1" size="size-8" />
            </button>
            <button
              class="cursor-pointer hover:scale-105 active:scale-95"
              phx-click="update-scheme-counter"
              phx-value-game_scheme_id={@game_scheme.id}
              phx-value-delta="1"
            >
              <.counter_token value="+1" size="size-8" />
            </button>
          </div>
        </div>
      </div>
      <.plain_card id={@game_scheme.id} card={@game_scheme.card} />
      <div class="absolute bottom-2 right-2 flex flex-col flex-reverse gap-1 pointer-events-none">
        <.threat_token :if={@game_scheme.threat > 0} value={@game_scheme.threat} />
        <.counter_token :if={@game_scheme.counter > 0} value={@game_scheme.counter} />
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :class, :string, default: ""
  attr :game_card, Sanctum.Games.GameCard, required: true
  attr :imgsrc, :string, default: nil
  attr :zone, :string, default: nil
  attr :show_tokens, :boolean, default: true

  def card(assigns) do
    assigns =
      assign(assigns, :src, assigns.imgsrc || assigns.game_card.card.image_url)
      |> assign(
        :aspect,
        if assigns.game_card.card && assigns.game_card.card.type in @landscape_types do
          "max-h-[71px] lg:max-h-[110px]"
        else
          "max-h-[100px] lg:max-h-[153px]"
        end
      )

    ~H"""
    <div
      id={@id}
      class={["relative group hover:z-100 group"]}
      tabindex="0"
      phx-click={JS.push("select-card", value: %{card_id: @game_card.id})}
    >
      <div
        id={@id <> "-drag"}
        class={[
          "game-card max-w-fit peer relative p-1 bg-black border border-gray-700 shadow shadow-black hover:z-50 focus:z-50",
          @zone == "hero_hand" &&
            "not-[.game-card-dragging]:transition-all hover:not-[.game-card-dragging]:scale-115 hover:not-[.game-card-dragging]:-translate-y-6",
          @class
        ]}
        phx-hook="CardDrag"
        data-game_card_id={@game_card.id}
        data-zone={@zone}
      >
        <.token_buttons_group :if={@show_tokens} game_card_id={@game_card.id} />
        <div class="relative">
          <figure class="rounded-[4.5%] overflow-hidden">
            <img class={[@aspect, "object-fit"]} src={@src} />
          </figure>
          <div class="absolute top-0 left-0 w-full h-full touch-none" />
        </div>
      </div>
      <div
        :if={@show_tokens}
        class="absolute bottom-2 right-2 flex flex-col flex-reverse gap-1 pointer-events-none"
      >
        <.threat_token :if={@game_card.threat > 0} value={@game_card.threat} />
        <.damage_token :if={@game_card.damage > 0} value={@game_card.damage} />
        <.counter_token :if={@game_card.counter > 0} value={@game_card.counter} />
      </div>
      <div class="pointer-events-none fixed left-2 bottom-2 hidden group-hover:not-peer-[.game-card-dragging]:block z-1000 p-3 bg-black ">
        <figure class="rounded-[4.5%] overflow-hidden">
          <img class={["h-[30vh] object-fit"]} src={@src} />
        </figure>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :card, Sanctum.Games.Card, default: nil
  attr :class, :string, default: ""
  attr :imgsrc, :string, default: nil

  def plain_card(assigns) do
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
    <div
      id={@id}
      class={[
        "game-card max-w-fit group peer relative p-1 bg-black border border-gray-700 shadow shadow-black hover:z-50 focus:z-50",
        @class
      ]}
    >
      <div class="relative">
        <figure class="rounded-[4.5%] overflow-hidden">
          <img class={[@aspect, "object-fit"]} src={@src} />
        </figure>
        <div class="absolute top-0 left-0 w-full h-full touch-none" />
      </div>
      <div class="pointer-events-none fixed left-2 bottom-2 hidden group-hover:not-peer-[.game-card-dragging]:block z-1000 p-3 bg-black ">
        <figure class="rounded-[4.5%] overflow-hidden">
          <img class={["h-[30vh] object-fit"]} src={@src} />
        </figure>
      </div>
    </div>
    """
  end

  def token_buttons_group(assigns) do
    ~H"""
    <div class={[
      "absolute pointer-events-none opacity-0 left-1/3 space-y-2 top-0 transition-all pt-[2px] pb-[4px] pl-[2px] pr-[4px] z-50",
      "sm:group-hover:not-peer-[.game-card-dragging]:opacity-100 sm:group-focus:not-peer-[.game-card-dragging]:opacity-100 group-hover:left-[85%] group-focus:left-[85%] group-hover:pointer-events-auto group-focus:pointer-events-auto"
    ]}>
      <div class="h-full w-full p-1 pr-2 pl-7 ">
        <.token_buttons game_card_id={@game_card_id} />
      </div>
    </div>
    """
  end

  attr :size, :string, default: "size-9"

  def token_buttons(assigns) do
    ~H"""
    <div class="grid grid-cols-[auto_auto] gap-1 items-center justify-center">
      <button
        class="cursor-pointer hover:scale-105 active:scale-95"
        phx-click="update-counter"
        phx-value-game_card_id={@game_card_id}
        phx-value-counter_type="threat"
        phx-value-delta="-1"
      >
        <.threat_token value="-1" size={@size} />
      </button>
      <button
        class="cursor-pointer hover:scale-105 active:scale-95"
        phx-click="update-counter"
        phx-value-game_card_id={@game_card_id}
        phx-value-counter_type="threat"
        phx-value-delta="1"
      >
        <.threat_token value="+1" size={@size} />
      </button>
      <button
        class="cursor-pointer hover:scale-105 active:scale-95"
        phx-click="update-counter"
        phx-value-game_card_id={@game_card_id}
        phx-value-counter_type="damage"
        phx-value-delta="-1"
      >
        <.damage_token value="-1" size={@size} />
      </button>
      <button
        class="cursor-pointer hover:scale-105 active:scale-95"
        phx-click="update-counter"
        phx-value-game_card_id={@game_card_id}
        phx-value-counter_type="damage"
        phx-value-delta="1"
      >
        <.damage_token value="+1" size={@size} />
      </button>
      <button
        class="cursor-pointer hover:scale-105 active:scale-95"
        phx-click="update-counter"
        phx-value-game_card_id={@game_card_id}
        phx-value-counter_type="counter"
        phx-value-delta="-1"
      >
        <.counter_token value="-1" size={@size} />
      </button>
      <button
        class="cursor-pointer hover:scale-105 active:scale-95"
        phx-click="update-counter"
        phx-value-game_card_id={@game_card_id}
        phx-value-counter_type="counter"
        phx-value-delta="1"
      >
        <.counter_token value="+1" size={@size} />
      </button>
    </div>
    """
  end

  attr :id, :string, required: true

  def encounter_back(assigns) do
    ~H"""
    <.plain_card id={@id} imgsrc={~p"/images/encounter-back.webp"} />
    """
  end

  attr :id, :string, required: true

  def player_back(assigns) do
    ~H"""
    <.plain_card id={@id} imgsrc={~p"/images/player-back.webp"} />
    """
  end

  attr :size, :string, default: "w-9 h-9"
  attr :value, :any, required: true

  def threat_token(assigns) do
    ~H"""
    <div class={[@size, "relative"]}>
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
        <span class="text-xl -mt-1 -mr-[2px] font-komika text-bold text-white text-shadow-[0_0_2px_black,0_0_2px_black,0_0_2px_black,0_0_2px_black]">
          {@value}
        </span>
      </div>
    </div>
    """
  end

  attr :size, :string, default: "w-9 h-9"

  def damage_token(assigns) do
    ~H"""
    <div class={[
      "relative rounded-full flex items-center justify-center bg-red-700 border-4 border-black",
      @size
    ]}>
      <span class="text-xl -mt-[2px] -mr-[1px] font-komika text-bold text-white text-shadow-[0_0_2px_black,0_0_2px_black,0_0_2px_black,0_0_2px_black]">
        {@value}
      </span>
    </div>
    """
  end

  attr :size, :string, default: "w-9 h-9"

  def counter_token(assigns) do
    ~H"""
    <div class={[
      "relative grid place-items-center rounded-lg bg-emerald-500 border-4 border-black",
      @size
    ]}>
      <span class="text-xl -mt-1 font-komika text-bold text-white text-shadow-[0_0_2px_black,0_0_2px_black,0_0_2px_black,0_0_2px_black]">
        {@value}
      </span>
    </div>
    """
  end
end
