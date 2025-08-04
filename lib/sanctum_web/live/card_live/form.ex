defmodule SanctumWeb.CardLive.Form do
  use SanctumWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage card records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="card-form" phx-change="validate" phx-submit="save">
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div class="space-y-4">
            <h3 class="text-lg font-semibold">Basic Information</h3>
            <.input field={@form[:name]} type="text" label="Name" />
            <.input field={@form[:subname]} type="text" label="Subname" />
            <.input field={@form[:code]} type="text" label="Code" />
            <.input
              field={@form[:type]}
              type="select"
              label="Type"
              options={[
                {"hero", "hero"},
                {"alter_ego", "alter_ego"},
                {"ally", "ally"},
                {"event", "event"},
                {"resource", "resource"},
                {"support", "support"},
                {"upgrade", "upgrade"},
                {"villain", "villain"},
                {"main_scheme", "main_scheme"},
                {"side_scheme", "side_scheme"},
                {"minion", "minion"},
                {"attachment", "attachment"},
                {"treachery", "treachery"},
                {"obligation", "obligation"},
                {"environment", "environment"}
              ]}
            />
            <.input
              field={@form[:aspect]}
              type="select"
              label="Aspect"
              options={[
                {"aggression", "aggression"},
                {"justice", "justice"},
                {"leadership", "leadership"},
                {"protection", "protection"},
                {"basic", "basic"},
                {"pool", "pool"}
              ]}
            />
            <.input field={@form[:cost]} type="number" label="Cost" />
            <.input field={@form[:text]} type="textarea" label="Text" />
            <.input field={@form[:traits]} type="text" label="Traits (comma-separated)" />
          </div>

          <div class="space-y-4">
            <h3 class="text-lg font-semibold">Game Stats</h3>
            <.input field={@form[:attack]} type="number" label="Attack" />
            <.input field={@form[:attack_cost]} type="number" label="Attack Cost" />
            <.input field={@form[:thwart]} type="number" label="Thwart" />
            <.input field={@form[:thwart_cost]} type="number" label="Thwart Cost" />
            <.input field={@form[:defense]} type="number" label="Defense" />
            <.input field={@form[:defense_cost]} type="number" label="Defense Cost" />
            <.input field={@form[:health]} type="number" label="Health" />
            <.input field={@form[:deck_limit]} type="number" label="Deck Limit" />
            <.input field={@form[:unique]} type="checkbox" label="Unique" />
            <.input field={@form[:permanent]} type="checkbox" label="Permanent" />
          </div>

          <div class="space-y-4">
            <h3 class="text-lg font-semibold">Icons</h3>
            <.input field={@form[:acceleration_icon]} type="checkbox" label="Acceleration Icon" />
            <.input field={@form[:amplify_icon]} type="checkbox" label="Amplify Icon" />
            <.input field={@form[:crisis_icon]} type="checkbox" label="Crisis Icon" />
            <.input field={@form[:hazard_icon]} type="checkbox" label="Hazard Icon" />
            <.input field={@form[:boost_star]} type="checkbox" label="Boost Star" />
          </div>

          <div class="space-y-4">
            <h3 class="text-lg font-semibold">Resources</h3>
            <.input field={@form[:resource_energy_count]} type="number" label="Energy Resources" />
            <.input field={@form[:resource_physical_count]} type="number" label="Physical Resources" />
            <.input field={@form[:resource_mental_count]} type="number" label="Mental Resources" />
            <.input field={@form[:resource_wild_count]} type="number" label="Wild Resources" />
          </div>

          <div class="space-y-4">
            <h3 class="text-lg font-semibold">Hero Fields</h3>
            <.input field={@form[:hand_size]} type="number" label="Hand Size" />
            <.input field={@form[:recover]} type="number" label="Recover" />
          </div>

          <div class="space-y-4">
            <h3 class="text-lg font-semibold">Villain/Scheme Fields</h3>
            <.input field={@form[:health_per_hero]} type="checkbox" label="Health Per Hero" />
            <.input field={@form[:stage]} type="number" label="Stage" />
            <.input field={@form[:base_threat]} type="number" label="Base Threat" />
            <.input field={@form[:escalation_threat]} type="number" label="Escalation Threat" />
          </div>

          <div class="space-y-4">
            <h3 class="text-lg font-semibold">Encounter Fields</h3>
            <.input field={@form[:boost]} type="number" label="Boost" />
          </div>

          <div class="space-y-4">
            <h3 class="text-lg font-semibold">Categorization</h3>
            <.input field={@form[:card_set]} type="text" label="Card Set" />
            <.input field={@form[:image_url]} type="text" label="Image URL" />
          </div>
        </div>

        <.button phx-disable-with="Saving..." variant="primary">Save Card</.button>
        <.button navigate={return_path(@return_to, @card)}>Cancel</.button>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    card =
      case params["id"] do
        nil -> nil
        id -> Ash.get!(Sanctum.Games.Card, id, actor: socket.assigns.current_user)
      end

    action = if is_nil(card), do: "New", else: "Edit"
    page_title = action <> " " <> "Card"

    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> assign(card: card)
     |> assign(:page_title, page_title)
     |> assign_form()}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  @impl true
  def handle_event("validate", %{"card" => card_params}, socket) do
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, card_params))}
  end

  def handle_event("save", %{"card" => card_params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: card_params) do
      {:ok, card} ->
        notify_parent({:saved, card})

        socket =
          socket
          |> put_flash(:info, "Card #{socket.assigns.form.source.type}d successfully")
          |> push_navigate(to: return_path(socket.assigns.return_to, card))

        {:noreply, socket}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp assign_form(%{assigns: %{card: card}} = socket) do
    form =
      if card do
        AshPhoenix.Form.for_update(card, :update, as: "card", actor: socket.assigns.current_user)
      else
        AshPhoenix.Form.for_create(Sanctum.Games.Card, :create,
          as: "card",
          actor: socket.assigns.current_user
        )
      end

    assign(socket, form: to_form(form))
  end

  defp return_path("index", _card), do: ~p"/cards"
  defp return_path("show", card), do: ~p"/cards/#{card.id}"
end
