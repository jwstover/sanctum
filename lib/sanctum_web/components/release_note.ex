defmodule SanctumWeb.Components.ReleaseNote do
  @moduledoc """
  One player-facing release note — tag, date, and rendered Markdown body in a
  `.panel`. Shared by the homepage "What's New" section and `/releases`.
  """

  use Phoenix.Component

  import SanctumWeb.CoreComponents, only: [panel: 1]

  attr :note, :map, required: true, doc: "a `Sanctum.ReleaseNotes.note()`"
  attr :rest, :global

  def release_note(assigns) do
    ~H"""
    <.panel class="px-5 py-5 sm:px-6" {@rest}>
      <div class="flex items-baseline justify-between gap-3">
        <span class="font-anton text-xl uppercase leading-none text-primary">
          {@note.tag}
        </span>
        <span class="font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/45">
          {Calendar.strftime(@note.date, "%b %-d, %Y")}
        </span>
      </div>
      <div class="deck-writeup release-notes mt-3">
        {Sanctum.ReleaseNotes.to_html(@note)}
      </div>
    </.panel>
    """
  end
end
