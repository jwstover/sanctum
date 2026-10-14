defmodule SanctumWeb.ReleaseNotesLive.Index do
  @moduledoc """
  Public `/releases` archive: every player-facing release note, newest first.
  The homepage "What's New" section shows only the latest few.
  """

  use SanctumWeb, :live_view

  on_mount {SanctumWeb.LiveUserAuth, :live_user_optional}

  import SanctumWeb.Components.ReleaseNote, only: [release_note: 1]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:releases}>
      <.header>
        Releases
      </.header>

      <div :if={@release_notes != []} id="release-notes" class="flex flex-col gap-3">
        <.release_note :for={note <- @release_notes} id={"release-#{note.tag}"} note={note} />
      </div>

      <.panel
        :if={@release_notes == []}
        id="release-notes-empty"
        class="border-dashed !border-[#2a2a30] px-6 py-12 text-center !shadow-none"
      >
        <div class="font-bangers text-3xl tracking-[0.02em] text-primary">No releases yet</div>
        <div class="mt-1.5 font-barlow text-sm text-base-content/55">
          Check back after the next update.
        </div>
      </.panel>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Releases")
     |> assign(:release_notes, Sanctum.ReleaseNotes.list())}
  end
end
