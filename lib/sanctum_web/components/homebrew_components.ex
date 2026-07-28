defmodule SanctumWeb.HomebrewComponents do
  @moduledoc """
  Shared HEEx components for the homebrew surfaces — the "storage not
  configured" notice and the alt-art grid — used by `HomebrewLive.Show`.
  """

  use SanctumWeb, :html

  import SanctumWeb.Components.CardSideTile

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
end
