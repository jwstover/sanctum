defmodule SanctumWeb.HomebrewLive.Show do
  @moduledoc """
  A homebrew project page — a light index of the project's sets, each with its
  card/alt counts, plus an inline (never modal) create-set form. Content is
  uploaded on the set page (`HomebrewLive.SetShow`), so this page has no
  upload affordance.
  """

  use SanctumWeb, :live_view

  alias Sanctum.Homebrew
  alias Sanctum.Homebrew.HomebrewSet

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Homebrew.get_project(id,
           actor: socket.assigns.current_user,
           load: [:card_count, :alt_count]
         ) do
      {:ok, project} ->
        {:ok,
         socket
         |> assign(:page_title, project.name)
         |> assign(:project, project)
         |> assign(:creating?, false)
         |> assign_sets()
         |> assign_form()}

      {:error, _not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found.")
         |> push_navigate(to: ~p"/homebrew")}
    end
  end

  @impl true
  def handle_event("start_create", _params, socket) do
    {:noreply, assign(socket, :creating?, true)}
  end

  def handle_event("cancel_create", _params, socket) do
    {:noreply, socket |> assign(:creating?, false) |> assign_form()}
  end

  def handle_event("validate", %{"set" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"set" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, set} ->
        {:noreply,
         push_navigate(socket, to: ~p"/homebrew/#{socket.assigns.project.id}/sets/#{set.id}")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  defp assign_sets(socket) do
    sets =
      socket.assigns.project.id
      |> Homebrew.list_project_sets!(
        actor: socket.assigns.current_user,
        load: [:card_count, :alt_count]
      )
      |> Enum.sort_by(& &1.inserted_at, DateTime)

    assign(socket, :sets, sets)
  end

  # The project id is never form input: it is pinned server-side on every
  # validate/submit (the create policy resolves ownership from it).
  defp assign_form(socket) do
    project_id = socket.assigns.project.id

    form =
      AshPhoenix.Form.for_create(HomebrewSet, :create,
        as: "set",
        actor: socket.assigns.current_user,
        prepare_params: fn params, _action ->
          Map.put(params, "homebrew_project_id", project_id)
        end
      )

    assign(socket, :form, to_form(form))
  end

  defp count_label(1, noun), do: "1 #{noun}"
  defp count_label(n, noun), do: "#{n} #{noun}s"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:homebrew}>
      <div class="mb-3">
        <.link
          navigate={~p"/homebrew"}
          class="font-barlow-condensed text-sm font-bold uppercase tracking-[0.08em] text-base-content/60 hover:text-primary"
        >
          ← Homebrew
        </.link>
      </div>

      <.header>
        {@project.name}
        <:actions>
          <.button :if={!@creating?} variant="primary" phx-click="start_create">
            New Set
          </.button>
        </:actions>
      </.header>

      <%!-- Not a header subtitle (that slot was dropped): the meta line is page
           content, and the "unofficial fan content" labeling is required on all
           homebrew surfaces (IP posture). --%>
      <p class="-mt-4 mb-5 font-barlow-condensed text-sm text-base-content/55">
        {count_label(length(@sets), "set")} &middot; {count_label(@project.card_count, "card")}<span :if={
          @project.alt_count > 0
        }> &middot; {count_label(@project.alt_count, "alt")}</span>
        &middot; unofficial fan content
      </p>

      <.panel :if={@creating?} class="mb-6 p-5">
        <.form for={@form} id="set-form" phx-change="validate" phx-submit="save">
          <div class="flex flex-col gap-4">
            <.input field={@form[:name]} type="text" label="Set name" autocomplete="off" />

            <div class="flex items-center gap-3">
              <.button variant="primary" type="submit">Create Set</.button>
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
        :if={@sets == [] and !@creating?}
        class="border-2 border-dashed border-neutral p-10 text-center"
      >
        <p class="font-barlow-condensed text-base-content/60">
          No sets yet. Create a set — a hero pack, a scenario — then upload its
          cards into it.
        </p>
      </div>

      <div class="flex flex-col gap-3">
        <.link :for={set <- @sets} navigate={~p"/homebrew/#{@project.id}/sets/#{set.id}"}>
          <.panel class="flex items-center justify-between gap-4 p-4 transition-transform hover:-translate-y-0.5">
            <div class="min-w-0">
              <div class="truncate font-anton text-base uppercase tracking-[0.05em]">
                {set.name}
              </div>
              <div class="font-barlow-condensed text-sm text-base-content/60">
                {count_label(set.card_count, "card")}
                <span :if={set.alt_count > 0}>
                  &middot; {count_label(set.alt_count, "alt")}
                </span>
              </div>
            </div>
          </.panel>
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
