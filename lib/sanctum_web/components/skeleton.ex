defmodule SanctumWeb.Components.Skeleton do
  @moduledoc """
  Loading placeholders for the async-mount pattern. Every LiveView paints its
  shell on the disconnected render (no DB) and streams real data in once the
  socket connects; these skeletons hold the layout in the gap so the page
  doesn't jump when content lands.

  `skeleton/1` is the pulsing-block primitive. The `*_skeleton` helpers compose
  it into the footprints the catalog pages actually render (card tiles, deck
  rows, detail panels).
  """
  use Phoenix.Component

  @doc "A single pulsing placeholder block. Size it with `class`."
  attr :class, :string, default: ""
  attr :rest, :global

  def skeleton(assigns) do
    ~H"""
    <div class={["animate-pulse bg-base-300", @class]} {@rest}></div>
    """
  end

  @doc """
  Grid of card-tile placeholders matching `SanctumWeb.Components.CardSideTile`.
  Used by the card pool and card admin table while the first page loads.
  """
  attr :count, :integer, default: 6

  def card_tile_skeleton_grid(assigns) do
    ~H"""
    <div class="grid grid-cols-1 items-start gap-[18px] sm:grid-cols-[repeat(auto-fill,minmax(452px,1fr))]">
      <.card_tile_skeleton :for={_ <- 1..@count} />
    </div>
    """
  end

  @doc "A single card-tile placeholder (landscape art frame + text lines)."
  def card_tile_skeleton(assigns) do
    ~H"""
    <div class="flex animate-pulse gap-[13px] border-2 border-neutral bg-base-200 p-2 shadow-comic">
      <div class="h-[180px] w-[128px] flex-none border-2 border-neutral bg-base-300"></div>
      <div class="flex min-w-0 flex-1 flex-col gap-2 py-1">
        <div class="h-2 w-1/3 bg-base-300"></div>
        <div class="h-5 w-2/3 bg-base-300"></div>
        <div class="mt-2 h-3 w-full bg-base-300"></div>
        <div class="h-3 w-5/6 bg-base-300"></div>
        <div class="h-3 w-4/6 bg-base-300"></div>
      </div>
    </div>
    """
  end

  @doc "Grid of deck-row placeholders matching the deck browser feed."
  attr :count, :integer, default: 6

  def deck_tile_skeleton_grid(assigns) do
    ~H"""
    <div class="grid grid-cols-1 items-start gap-3 sm:grid-cols-[repeat(auto-fill,minmax(520px,1fr))]">
      <div
        :for={_ <- 1..@count}
        class="flex animate-pulse items-stretch gap-3 border-2 border-neutral bg-base-200 p-3 shadow-comic sm:gap-4 sm:p-3.5"
      >
        <div class="h-[151px] w-[108px] flex-none border-2 border-neutral bg-base-300"></div>
        <div class="flex min-w-0 flex-1 flex-col gap-2.5 py-1">
          <div class="h-3 w-24 bg-base-300"></div>
          <div class="mt-1 h-6 w-2/3 bg-base-300"></div>
          <div class="h-3 w-full bg-base-300"></div>
          <div class="h-3 w-1/2 bg-base-300"></div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Generic tile grid placeholder for pack-style card grids (browse pages).
  Renders `count` portrait art frames.
  """
  attr :count, :integer, default: 8
  attr :class, :string, default: "grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4"

  def art_grid_skeleton(assigns) do
    ~H"""
    <div class={@class}>
      <div
        :for={_ <- 1..@count}
        class="aspect-[5/7] animate-pulse border-2 border-neutral bg-base-300 shadow-comic-sm"
      >
      </div>
    </div>
    """
  end

  @doc "Full-width detail-panel placeholder for single-record detail pages."
  def detail_skeleton(assigns) do
    ~H"""
    <div class="animate-pulse space-y-4">
      <div class="flex flex-col gap-6 sm:flex-row">
        <div class="aspect-[5/7] w-full max-w-[280px] flex-none border-2 border-neutral bg-base-300 shadow-comic">
        </div>
        <div class="flex min-w-0 flex-1 flex-col gap-3">
          <div class="h-4 w-28 bg-base-300"></div>
          <div class="h-9 w-3/4 bg-base-300"></div>
          <div class="mt-2 h-3 w-full bg-base-300"></div>
          <div class="h-3 w-11/12 bg-base-300"></div>
          <div class="h-3 w-5/6 bg-base-300"></div>
          <div class="mt-4 h-3 w-2/3 bg-base-300"></div>
        </div>
      </div>
    </div>
    """
  end
end
