defmodule SanctumWeb.EventLive.New do
  @moduledoc false

  use SanctumWeb, :live_view

  alias Sanctum.Events

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Event")
     |> assign_form()}
  end

  def handle_event("create", %{"form" => params}, socket) do
    user = socket.assigns.current_user

    case Events.create_event(params, actor: user) do
      {:ok, event} ->
        {:noreply, push_navigate(socket, to: ~p"/events/#{event.id}/setup")}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:form, to_form(form))
         |> put_flash(:error, "Could not create the event")}
    end
  end

  defp assign_form(socket) do
    form =
      Sanctum.Events.Event
      |> AshPhoenix.Form.for_create(:create, as: "form", actor: socket.assigns.current_user)
      |> to_form()

    assign(socket, :form, form)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:events}>
      <.header>New Event</.header>

      <.form for={@form} phx-submit="create" class="max-w-md space-y-4">
        <.input type="text" field={@form[:name]} label="Event name" placeholder="Saturday Loki Night" />
        <.input
          type="number"
          field={@form[:time_limit_minutes]}
          label="Time limit (minutes)"
          value={@form[:time_limit_minutes].value || 180}
          min="1"
        />

        <div class="flex gap-2">
          <.button phx-disable-with="Creating..." variant="primary" type="submit">
            Create &amp; build roster
          </.button>
          <.button variant="ghost" navigate={~p"/events"}>Cancel</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
