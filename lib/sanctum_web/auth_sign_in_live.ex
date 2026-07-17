defmodule SanctumWeb.AuthSignInLive do
  @moduledoc """
  Drop-in replacement for `AshAuthentication.Phoenix.SignInLive` (wired via
  `sign_in_route`'s `live_view:` option). The `:sign_in` and `:reset` actions
  render the stock `Components.SignIn` exactly as the library LiveView does;
  `:register` renders our own form backed by the enumeration-safe
  `:request_registration` action, which responds "check your email" whether
  or not the address already has an account.
  """

  use SanctumWeb, :live_view

  # The stock auth components emit flash as a {:put_flash, ...} message to
  # their parent LiveView; this hook (which the stock SignInLive gets from
  # AshAuthentication.Phoenix.Web) turns it into real flash. Without it the
  # reset form's "check your email" feedback silently vanishes.
  on_mount AshAuthentication.Phoenix.Utils.Flash

  alias AshAuthentication.Phoenix.Components
  alias SanctumWeb.AuthOverrides

  @impl true
  def mount(_params, session, socket) do
    overrides = Map.get(session, "overrides", [AshAuthentication.Phoenix.Overrides.Default])

    socket =
      socket
      |> assign(overrides: overrides)
      |> assign_new(:otp_app, fn -> nil end)
      |> assign(:path, session["path"] || "/")
      |> assign(:reset_path, session["reset_path"])
      |> assign(:register_path, session["register_path"])
      |> assign(:current_tenant, session["tenant"])
      |> assign(:resources, session["resources"])
      |> assign(:context, session["context"] || %{})
      |> assign(:auth_routes_prefix, session["auth_routes_prefix"])
      |> assign(:gettext_fn, session["gettext_fn"])
      |> assign(:sent?, false)
      |> assign_register_form()

    {:ok, socket}
  end

  defp assign_register_form(socket) do
    form =
      AshPhoenix.Form.for_action(Sanctum.Accounts.User, :request_registration,
        as: "user",
        authorize?: false
      )

    assign(socket, :form, to_form(form))
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    {:noreply,
     assign(socket, :form, to_form(AshPhoenix.Form.validate(socket.assigns.form.source, params)))}
  end

  def handle_event("submit", %{"user" => params}, socket) do
    # :request_registration returns nothing, so a successful submit is a bare
    # :ok rather than the {:ok, result} shape of record-returning actions.
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}

      _ok ->
        {:noreply,
         socket
         |> assign(:sent?, true)
         |> assign(:submitted_email, params["email"])}
    end
  end

  @impl true
  def render(%{live_action: :register} = assigns) do
    ~H"""
    <div class={AuthOverrides.page_class()}>
      <Layouts.flash_group flash={@flash} />
      <div class={AuthOverrides.panel_class()}>
        <div class="w-full pb-6 mb-6 border-b-2 border-neutral text-center">
          <.link navigate="/" class="font-bangers text-[40px] leading-none tracking-wide text-primary">
            SANCTUM
          </.link>
        </div>

        <%= if @sent? do %>
          <h2 class={AuthOverrides.heading_class()}>Check your email</h2>
          <p class="font-barlow text-sm text-base-content/80">
            We've sent a link to <span class="font-semibold">{@submitted_email}</span> to
            finish setting up your account. It expires in three days.
          </p>
          <.link navigate={@path} class={[AuthOverrides.button_ghost(), "mt-6"]}>
            Back to sign in
          </.link>
        <% else %>
          <h2 class={AuthOverrides.heading_class()}>Register</h2>

          <.form for={@form} phx-change="validate" phx-submit="submit" class="mt-2 mb-2">
            <.register_input field={@form[:email]} type="email" label="Email" autocomplete="email" />
            <.register_input
              field={@form[:password]}
              type="password"
              label="Password"
              autocomplete="new-password"
            />
            <.register_input
              field={@form[:password_confirmation]}
              type="password"
              label="Password Confirmation"
              autocomplete="new-password"
            />

            <div class="flex flex-row justify-between content-between mt-3">
              <.auth_link navigate={@reset_path || "/reset"}>Forgot your password?</.auth_link>
              <.auth_link navigate={@path}>Already have an account?</.auth_link>
            </div>

            <button type="submit" class={[AuthOverrides.button_primary(), "mt-5"]}>
              Register
            </button>
          </.form>

          <div class="relative my-5">
            <div class="w-full border-t-2 border-neutral"></div>
            <div class="absolute inset-0 flex items-center justify-center -top-2">
              <span class="px-3 bg-base-200 font-ibm-mono text-[10px] uppercase tracking-[0.2em] text-base-content/50">
                or
              </span>
            </div>
          </div>

          <div class="w-full mt-2 mb-2">
            <a href={oauth_path(@auth_routes_prefix, "google")} class={AuthOverrides.button_ghost()}>
              <Components.OAuth2.icon icon={:google} overrides={@overrides} icon_src={nil} />
              Sign in with Google
            </a>
          </div>

          <div class="w-full mt-2 mb-2">
            <a href={oauth_path(@auth_routes_prefix, "discord")} class={AuthOverrides.button_ghost()}>
              <Components.OAuth2.icon
                icon={:discord}
                overrides={@overrides}
                icon_src="/images/discord-mark.svg"
              /> Sign in with Discord
            </a>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class={AuthOverrides.page_class()}>
      <Layouts.flash_group flash={@flash} />
      <.live_component
        module={Components.SignIn}
        otp_app={@otp_app}
        live_action={@live_action}
        path={@path}
        auth_routes_prefix={@auth_routes_prefix}
        resources={@resources}
        reset_path={@reset_path}
        register_path={@register_path}
        id="sign-in"
        overrides={@overrides}
        current_tenant={@current_tenant}
        context={@context}
        gettext_fn={@gettext_fn}
      />
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :type, :string, required: true
  attr :label, :string, required: true
  attr :autocomplete, :string, required: true

  defp register_input(assigns) do
    ~H"""
    <div class="mt-3">
      <label for={@field.id} class={AuthOverrides.field_label_class()}>{@label}</label>
      <input
        type={@type}
        name={@field.name}
        id={@field.id}
        value={@field.value}
        autocomplete={@autocomplete}
        class={
          if @field.errors == [],
            do: AuthOverrides.input_class(),
            else: AuthOverrides.input_error_class()
        }
      />
      <ul :if={@field.errors != []} class="font-barlow text-sm text-error mt-2 space-y-1">
        <li :for={error <- @field.errors}>{translate_error(error)}</li>
      </ul>
    </div>
    """
  end

  slot :inner_block, required: true
  attr :navigate, :string, required: true

  defp auth_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="flex-none px-2 first:pl-0 last:pr-0 font-barlow-condensed text-[13px] font-bold uppercase tracking-[0.06em] text-primary hover:underline underline-offset-4"
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp oauth_path(nil, strategy), do: "/auth/user/" <> strategy
  defp oauth_path(prefix, strategy), do: prefix <> "/user/" <> strategy
end
