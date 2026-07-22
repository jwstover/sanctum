defmodule SanctumWeb.HomebrewLive.Index do
  @moduledoc """
  The signed-in user's homebrew projects: a list of their projects plus an
  inline (never modal) create form with the upload attestation. The public
  directory is a later phase — this page only ever shows your own work.
  """

  use SanctumWeb, :live_view

  alias Sanctum.Homebrew
  alias Sanctum.Homebrew.HomebrewProject

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Homebrew")
     |> assign(:creating?, false)
     |> assign_projects()
     |> assign_form()}
  end

  @impl true
  def handle_event("start_create", _params, socket) do
    {:noreply, assign(socket, :creating?, true)}
  end

  def handle_event("cancel_create", _params, socket) do
    {:noreply, socket |> assign(:creating?, false) |> assign_form()}
  end

  def handle_event("validate", %{"project" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"project" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, project} ->
        {:noreply, push_navigate(socket, to: ~p"/homebrew/#{project.id}")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  defp assign_projects(socket) do
    projects =
      Homebrew.list_my_projects!(
        actor: socket.assigns.current_user,
        load: [:card_count]
      )

    assign(socket, :projects, projects)
  end

  defp assign_form(socket) do
    form =
      AshPhoenix.Form.for_create(HomebrewProject, :create,
        as: "project",
        actor: socket.assigns.current_user
      )

    assign(socket, :form, to_form(form))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:homebrew}>
      <.header>
        Homebrew
        <:actions>
          <.button :if={!@creating?} variant="primary" phx-click="start_create">
            New Project
          </.button>
        </:actions>
      </.header>

      <.panel :if={@creating?} class="mb-6 p-5">
        <.form for={@form} id="project-form" phx-change="validate" phx-submit="save">
          <div class="flex flex-col gap-4">
            <.input field={@form[:name]} type="text" label="Project name" autocomplete="off" />

            <.input
              field={@form[:attestation]}
              type="checkbox"
              label="This is my own work, or it is shared with the creator's permission."
            />

            <div class="flex items-center gap-3">
              <.button variant="primary" type="submit">Create Project</.button>
              <button
                type="button"
                phx-click="cancel_create"
                class="font-barlow-condensed text-sm font-bold uppercase tracking-[0.08em] text-base-content/60 hover:text-base-content"
              >
                Cancel
              </button>
            </div>
          </div>
        </.form>
      </.panel>

      <div
        :if={@projects == [] and !@creating?}
        class="border-2 border-dashed border-neutral p-10 text-center"
      >
        <p class="font-barlow-condensed text-base-content/60">
          No projects yet. Create one and drop card images in — every image is
          already a playable card.
        </p>
      </div>

      <div class="flex flex-col gap-3">
        <.link :for={project <- @projects} navigate={~p"/homebrew/#{project.id}"}>
          <.panel class="flex items-center justify-between gap-4 p-4 transition-transform hover:-translate-y-0.5">
            <div class="min-w-0">
              <div class="truncate font-anton text-base uppercase tracking-[0.05em]">
                {project.name}
              </div>
              <div class="font-barlow-condensed text-sm text-base-content/60">
                {project.card_count} {if project.card_count == 1, do: "card", else: "cards"}
              </div>
            </div>
            <span class="shrink-0 border-2 border-neutral bg-base-300 px-2 py-0.5 font-barlow-condensed text-xs font-bold uppercase tracking-[0.07em]">
              {project.visibility}
            </span>
          </.panel>
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
