defmodule SanctumWeb.Components.Collection do
  @moduledoc """
  Collection-status UI: the "owned" chip and the add/remove toggle button.
  Callers gate rendering on `@current_user` — collection state never renders
  for anonymous visitors.
  """
  use Phoenix.Component

  import SanctumWeb.CoreComponents, only: [icon: 1]

  @doc """
  A small comic-style chip marking something as in the user's collection.
  """
  attr :class, :any, default: nil
  attr :label, :string, default: "Owned"

  def owned_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex flex-none items-center gap-0.5 border border-primary/60 bg-primary/15 px-1.5 py-px",
      "font-ibm-mono text-[9px] uppercase leading-4 tracking-[0.14em] text-primary",
      @class
    ]}>
      <.icon name="hero-check" class="size-2.5" />
      {@label}
    </span>
    """
  end

  @doc """
  The add/remove collection toggle. Emits `@event` with `phx-value-id={@id}`;
  the handler owns the actual tri-state semantics (`Sanctum.Collections`).

  `compact` renders an icon-only square for per-card chips in dense grids.
  """
  attr :owned, :boolean, required: true
  attr :event, :string, required: true
  attr :id, :string, required: true, doc: "pack or card id sent as phx-value-id"
  attr :compact, :boolean, default: false
  attr :title, :string, default: nil, doc: "hover text; defaults by owned state"
  attr :class, :any, default: nil

  def collection_toggle(assigns) do
    assigns =
      assign_new(assigns, :hover_title, fn ->
        assigns.title || ((assigns.owned && "Remove from collection") || "Add to collection")
      end)

    ~H"""
    <button
      phx-click={@event}
      phx-value-id={@id}
      title={@hover_title}
      class={
        [
          "inline-flex cursor-pointer items-center justify-center gap-1.5 transition-colors",
          # Compact: a quiet translucent chip over card art; green check = owned.
          @compact && "size-6 rounded-[4px] bg-base-100/75",
          @compact &&
            ((@owned && "text-success hover:text-error") || "text-white/50 hover:text-success"),
          # Full: the comic neutral button; green text = owned.
          !@compact && "border-2 border-neutral bg-base-300 px-3 py-1.5",
          !@compact &&
            ((@owned && "text-success hover:border-success") ||
               "text-base-content/70 hover:border-primary hover:text-primary"),
          @class
        ]
      }
    >
      <.icon name={(@owned && "hero-check") || "hero-plus"} class="size-3.5 flex-none" />
      <span
        :if={!@compact}
        class="font-barlow-condensed text-[12px] font-bold uppercase tracking-[0.07em]"
      >
        {(@owned && "In Collection") || "Add to Collection"}
      </span>
    </button>
    """
  end
end
