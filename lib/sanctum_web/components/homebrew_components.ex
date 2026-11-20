defmodule SanctumWeb.HomebrewComponents do
  @moduledoc """
  Shared HEEx components for the homebrew surfaces — the "storage not
  configured" notice, the alt-art grid, the set details block and the
  unofficial-fan-content label — shared by the workspace pages and the
  public set pages.
  """

  use SanctumWeb, :html

  import SanctumWeb.Components.CardSideTile

  alias SanctumWeb.HomebrewLive.Support

  @doc "Notice shown when the S3 image storage env vars are absent."
  def upload_unconfigured_notice(assigns) do
    ~H"""
    <.panel class="mb-6 p-5">
      <p class="font-barlow-condensed text-base-content/70">
        Image storage is not configured — set the S3 environment variables
        (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_ENDPOINT_URL_S3, BUCKET_NAME)
        to enable uploads.
      </p>
    </.panel>
    """
  end

  @doc """
  The alt-art grid: each alt rendered as its target side's tile wearing the
  custom art, with a fan-art credit and a delete action. `revert?` adds the
  "revert to a standalone card" action (project page only).
  """
  attr :alt_tiles, :list, required: true
  attr :count, :integer, required: true
  attr :revert?, :boolean, default: false
  attr :class, :string, default: nil

  def alt_art_section(assigns) do
    ~H"""
    <div :if={@alt_tiles != []} class={@class}>
      <h2 class="mb-3 font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/50">
        Alt Art ({@count})
      </h2>
      <div class="grid grid-cols-1 items-start gap-[18px] pb-28 sm:grid-cols-[repeat(auto-fill,minmax(452px,1fr))]">
        <.card_side_tile
          :for={{alt, side} <- @alt_tiles}
          side={side}
          size="md"
          navigate={~p"/cards/#{alt.card_id}"}
        >
          <:actions>
            <span class="font-ibm-mono text-xs uppercase tracking-[0.16em] text-base-content/50">
              fan art{alt.artist && " · by #{alt.artist}"}
            </span>
            <.button
              :if={@revert?}
              variant="ghost"
              phx-click={open_confirm("confirm-revert-alt-#{alt.id}")}
              class="ml-auto px-3 py-1.5"
            >
              Revert
            </.button>
            <.confirm_dialog
              :if={@revert?}
              id={"confirm-revert-alt-#{alt.id}"}
              message="Convert back to a standalone card in this project?"
              confirm_label="Revert"
              phx-click="revert_alt"
              phx-value-id={alt.id}
            />
            <.button
              variant="ghost"
              phx-click={open_confirm("confirm-del-alt-#{alt.id}")}
              class={"#{(!@revert? && "ml-auto ") || ""}px-3 py-1.5 text-error hover:text-error"}
            >
              Delete
            </.button>
            <.confirm_dialog
              id={"confirm-del-alt-#{alt.id}"}
              message="Delete this alt art permanently?"
              confirm_label="Delete alt art"
              phx-click="delete_alt"
              phx-value-id={alt.id}
            />
          </:actions>
        </.card_side_tile>
      </div>
    </div>
    """
  end

  @doc """
  The "unofficial fan content" label every public homebrew surface carries:
  community-made, not affiliated with or endorsed by the game's publishers.
  `compact` renders the one-line badge form for tiles and headers.
  """
  attr :id, :string, default: nil
  attr :compact, :boolean, default: false
  attr :class, :any, default: nil

  def fan_content_notice(%{compact: true} = assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        "inline-flex items-center border-2 border-neutral bg-base-300 px-1.5 py-0.5 font-ibm-mono text-[10px] uppercase tracking-[0.14em] text-warning",
        @class
      ]}
    >
      Unofficial fan content
    </span>
    """
  end

  def fan_content_notice(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "flex items-start gap-2.5 border-2 border-dashed border-warning/60 bg-base-200 px-4 py-3",
        @class
      ]}
    >
      <.icon name="hero-exclamation-triangle" class="mt-0.5 size-4 flex-none text-warning" />
      <p class="font-barlow-condensed text-sm text-base-content/70">
        <span class="font-bold uppercase tracking-[0.08em] text-warning">
          Unofficial fan content.
        </span>
        Made by the community — not affiliated with, endorsed by or produced by
        Fantasy Flight Games or Marvel. Card images and text belong to their creators.
      </p>
    </div>
    """
  end

  @doc """
  The set's public-facing metadata: banner, kind + tags, and the rendered
  markdown description. Renders nothing for an undescribed set. Expects
  `set_kind` loaded.
  """
  attr :set, :any, required: true

  def set_details(assigns) do
    assigns =
      assigns
      |> assign(:banner, Support.banner_src(assigns.set.banner_url))
      |> assign(:description, Support.description_html(assigns.set.description))

    ~H"""
    <div
      :if={@banner || @set.set_kind || @set.tags != [] || @description}
      id="set-details"
      class="mb-8 flex flex-col gap-4"
    >
      <div :if={@banner} class="overflow-hidden border-2 border-neutral bg-base-300 shadow-comic">
        <img
          src={@banner}
          alt={"#{@set.name} banner"}
          class="max-h-[320px] w-full object-cover"
        />
      </div>

      <div :if={@set.set_kind || @set.tags != []} class="flex flex-wrap items-center gap-2">
        <span
          :if={@set.set_kind}
          id="set-kind"
          class="border-2 border-neutral bg-primary px-2 py-0.5 font-barlow-condensed text-xs font-bold uppercase tracking-[0.08em] text-primary-content"
        >
          {@set.set_kind.label}
        </span>
        <span
          :for={tag <- @set.tags}
          class="border-2 border-neutral bg-base-300 px-2 py-0.5 font-barlow-condensed text-xs font-bold uppercase tracking-[0.06em] text-base-content/70"
        >
          {tag}
        </span>
      </div>

      <div
        :if={@description}
        id="set-description"
        class="deck-writeup max-w-3xl"
      >
        {@description}
      </div>
    </div>
    """
  end
end
