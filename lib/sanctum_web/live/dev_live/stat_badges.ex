defmodule SanctumWeb.DevLive.StatBadges do
  @moduledoc """
  Dev playground for refining the comic stat badges (`SanctumWeb.Components.StatBadge`).
  Not part of the game UI — a scratch page to eyeball the badges at different
  values, sizes, and colors while we iterate. Route: /dev/stat-badges.
  """
  use SanctumWeb, :live_view

  import SanctumWeb.Components.HealthBadge
  import SanctumWeb.Components.StatBadge

  on_mount {SanctumWeb.LiveUserAuth, :live_user_optional}

  @stats [:thw, :atk, :def, :sch, :hp]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       value: "3",
       size: 120,
       consequential: 0,
       star: false,
       stats: @stats,
       page_title: "Stat Badges"
     )}
  end

  @impl true
  def handle_event("update", params, socket) do
    {:noreply,
     assign(socket,
       value: params["value"] || socket.assigns.value,
       size: String.to_integer(params["size"] || to_string(socket.assigns.size)),
       consequential:
         String.to_integer(params["consequential"] || to_string(socket.assigns.consequential)),
       star: params["star"] == "true"
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-5xl px-6 py-10 space-y-10">
      <header class="space-y-1">
        <p class="text-xs uppercase tracking-[0.2em] text-red-500 font-black">Sanctum · Dev</p>
        <h1 class="text-3xl font-black italic uppercase">Comic stat badges</h1>
        <p class="text-sm text-base-content/60 max-w-prose">
          Playground for <code>SanctumWeb.Components.StatBadge</code>. Edit the component to refine
          geometry, halftone, or colors; this page just renders it.
        </p>
      </header>

      <form phx-change="update" class="flex flex-wrap items-center gap-6">
        <label class="flex items-center gap-2 text-sm">
          <span class="uppercase tracking-widest text-xs font-bold text-base-content/70">Value</span>
          <input
            type="text"
            name="value"
            value={@value}
            class="w-16 rounded-md border border-base-300 bg-base-200 px-2 py-1 font-mono"
          />
        </label>
        <label class="flex items-center gap-2 text-sm flex-1 min-w-[220px]">
          <span class="uppercase tracking-widest text-xs font-bold text-base-content/70">Size</span>
          <input type="range" name="size" min="48" max="220" value={@size} class="flex-1" />
          <span class="font-mono w-10 text-right">{@size}</span>
        </label>
        <label class="flex items-center gap-2 text-sm">
          <span class="uppercase tracking-widest text-xs font-bold text-base-content/70">Conseq.</span>
          <input type="range" name="consequential" min="0" max="4" value={@consequential} />
          <span class="font-mono w-6 text-right">{@consequential}</span>
        </label>
        <label class="flex cursor-pointer items-center gap-2 text-sm">
          <input type="hidden" name="star" value="false" />
          <input type="checkbox" name="star" value="true" checked={@star} />
          <span class="uppercase tracking-widest text-xs font-bold text-base-content/70">Star</span>
        </label>
      </form>

      <section class="space-y-3">
        <h2 class="text-sm uppercase tracking-widest font-black border-b-2 border-current pb-1">
          On dark
        </h2>
        <div class="bg-base-200 bg-halftone flex flex-wrap items-start gap-8 rounded-xl p-8">
          <div :for={stat <- @stats} class="flex flex-col items-center gap-2">
            <.stat_badge
              stat={stat}
              value={@value}
              size={@size}
              consequential={@consequential}
              star={@star}
            />
            <span class="text-xs uppercase tracking-widest text-white/50 font-bold">{stat}</span>
          </div>
        </div>
      </section>

      <section class="space-y-3">
        <h2 class="text-sm uppercase tracking-widest font-black border-b-2 border-current pb-1">
          On light
        </h2>
        <div class="flex flex-wrap items-start gap-8 rounded-xl p-8 bg-base-200">
          <.stat_badge
            :for={stat <- @stats}
            stat={stat}
            value={@value}
            size={@size}
            consequential={@consequential}
            star={@star}
          />
        </div>
      </section>

      <section class="space-y-3">
        <h2 class="text-sm uppercase tracking-widest font-black border-b-2 border-current pb-1">
          Health badge
        </h2>
        <div class="bg-base-200 bg-halftone flex flex-wrap items-center gap-8 rounded-xl p-8">
          <div class="flex flex-col items-center gap-2">
            <.health_badge value={@value} size={@size} />
            <span class="text-xs uppercase tracking-widest text-white/50 font-bold">hp</span>
          </div>
          <div class="flex flex-col items-center gap-2">
            <.health_badge value="12" size={@size} />
            <span class="text-xs uppercase tracking-widest text-white/50 font-bold">
              two digits
            </span>
          </div>
          <div class="flex flex-col items-center gap-2">
            <.health_badge value={@value} size={@size} player />
            <span class="text-xs uppercase tracking-widest text-white/50 font-bold">
              per player
            </span>
          </div>
        </div>
      </section>

      <section class="space-y-3">
        <h2 class="text-sm uppercase tracking-widest font-black border-b-2 border-current pb-1">
          Custom colors (bright + dark overrides)
        </h2>
        <div class="bg-base-200 flex flex-wrap items-start gap-8 rounded-xl p-8">
          <.stat_badge value={@value} size={@size} label="POW" bright="#ff7a00" dark="#a33c00" />
          <.stat_badge value={@value} size={@size} label="ARM" bright="#8a8f98" dark="#3a3d44" />
          <.stat_badge value={@value} size={@size} label="SPD" bright="#12b886" dark="#0a6b4f" />
          <.stat_badge value={@value} size={@size} label="PSY" bright="#e64980" dark="#8a1d48" />
        </div>
      </section>
    </div>
    """
  end
end
