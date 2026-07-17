defmodule SanctumWeb.ProfileLive.Index do
  @moduledoc """
  The signed-in user's profile: claim (or change) a username, preview the
  avatar. Account settings (change password, linked sign-in methods) will
  stack on this page later.
  """
  use SanctumWeb, :live_view

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:profile}>
      <div class="mx-auto max-w-xl">
        <h1 class="font-anton text-3xl uppercase leading-[0.9] tracking-[0.005em] md:text-[42px]">
          Profile
        </h1>

        <.panel class="mt-6 p-5">
          <div class="flex items-center gap-4 border-b-2 border-neutral pb-5">
            <.avatar
              name={display_name(@current_user)}
              url={@current_user.avatar_url}
              seed={display_name(@current_user)}
              size="lg"
            />
            <div class="min-w-0">
              <div class="truncate font-bangers text-[26px] leading-none tracking-wide text-primary">
                {display_name(@current_user)}
              </div>
              <div class="mt-1.5 truncate font-ibm-mono text-xs text-base-content/50">
                {@current_user.email}
              </div>
            </div>
          </div>

          <.form for={@form} id="profile-form" phx-change="validate" phx-submit="save" class="mt-5">
            <.input
              field={@form[:username]}
              type="text"
              label="Username"
              autocomplete="username"
              placeholder="e.g. web_head"
            />
            <p class="mt-2 font-barlow-condensed text-[13px] text-base-content/50">
              3–20 characters: letters, numbers, and underscores. Shown on your decks.
            </p>
            <.button variant="primary" type="submit" class="mt-4">
              Save username
            </.button>
          </.form>
        </.panel>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_form(socket)}
  end

  @impl true
  def handle_event("validate", %{"profile" => params}, socket) do
    {:noreply,
     assign(socket, :form, to_form(AshPhoenix.Form.validate(socket.assigns.form.source, params)))}
  end

  def handle_event("save", %{"profile" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_user, user)
         |> assign_form()
         |> put_flash(:info, "Username saved.")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  defp assign_form(socket) do
    user = socket.assigns.current_user

    form =
      AshPhoenix.Form.for_update(user, :update_profile,
        as: "profile",
        actor: user
      )

    assign(socket, :form, to_form(form))
  end

  defp display_name(%{username: username}) when not is_nil(username), do: "@#{username}"
  defp display_name(%{email: email}), do: to_string(email)
end
