defmodule SanctumWeb.CardLive.Form do
  use SanctumWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage card records in your database.</:subtitle>
      </.header>

      <.form for={@card_form} id="card-form" phx-change="validate" phx-submit="save">
        <!-- Card Information -->
        <div class="mb-8">
          <h3 class="text-lg font-semibold mb-4">Card Information</h3>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <.input field={@card_form[:base_code]} type="text" label="Base Code" />
            <.input field={@card_form[:code]} type="text" label="Primary Code" />
            <.input field={@card_form[:set]} type="text" label="Set" />
            <.input field={@card_form[:pack]} type="text" label="Pack" />
            <.input field={@card_form[:deck_limit]} type="number" label="Deck Limit" />
            <.input field={@card_form[:unique]} type="checkbox" label="Unique" />
            <.input field={@card_form[:permanent]} type="checkbox" label="Permanent" />
            <.input field={@card_form[:is_multi_sided]} type="checkbox" label="Multi-sided" />
          </div>
        </div>

        <div class="space-y-6">
          <h3 class="text-lg font-semibold">Card Sides</h3>
          <.inputs_for :let={card_side} field={@card_form[:card_sides]}>
            <div class="border rounded-lg p-6 bg-blue-50 border-blue-200">
              <.card_side_form form={card_side} />
            </div>
          </.inputs_for>
        </div>

        <div class="mt-8 flex gap-4">
          <.button phx-disable-with="Saving..." variant="primary">Save Card</.button>
          <.button navigate={return_path(@return_to, @card)}>Cancel</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    card =
      case params["id"] do
        nil ->
          nil

        id ->
          Ash.get!(Sanctum.Games.Card, id,
            actor: socket.assigns.current_user,
            load: [:card_sides]
          )
      end

    action = if is_nil(card), do: "New", else: "Edit"
    page_title = action <> " " <> "Card"

    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> assign(card: card)
     |> assign(:page_title, page_title)
     |> assign_forms()}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  @impl true
  def handle_event("validate", params, socket) do
    card_params = params["card"] || %{}
    validated_card_form = AshPhoenix.Form.validate(socket.assigns.card_form, card_params)

    {:noreply, socket |> assign(card_form: validated_card_form)}
  end

  def handle_event("save", params, socket) do
    card_params =
      (params["card"] || %{})
      |> update_traits()

    case AshPhoenix.Form.submit(socket.assigns.card_form, params: card_params) do
      {:ok, card} ->
        notify_parent({:saved, card})

        socket =
          socket
          |> put_flash(:info, "Card saved successfully")
          |> push_navigate(to: return_path(socket.assigns.return_to, card))

        {:noreply, socket}

      {:error, card_form} ->
        {:noreply, assign(socket, card_form: card_form)}
    end
  end

  defp update_traits(%{"card_sides" => %{}} = params) do
    Map.update(params, "card_sides", %{}, fn sides_map ->
      Enum.reduce(sides_map, sides_map, fn {k, _}, acc ->
        Map.update(acc, k, %{}, &put_side_traits/1)
      end)
    end)
  end

  defp update_traits(params), do: params

  defp put_side_traits(side) do
    traits =
      side
      |> Map.get("traits_string")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    Map.put(side, "traits", traits)
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  # Stats are stored as Sanctum.Games.Stat structs; the number inputs edit only
  # the value (a bare number casts to a flat, unstarred stat).
  defp stat_value(%Sanctum.Games.Stat{value: value}), do: value
  defp stat_value(value) when is_integer(value) or is_binary(value), do: value
  defp stat_value(_), do: nil

  defp assign_forms(%{assigns: %{card: card}} = socket) do
    card_form =
      if card do
        AshPhoenix.Form.for_update(card, :update_with_sides,
          as: "card",
          actor: socket.assigns.current_user
        )
      else
        AshPhoenix.Form.for_create(Sanctum.Games.Card, :create_with_sides,
          as: "card",
          actor: socket.assigns.current_user
        )
      end

    socket
    |> assign(card_form: to_form(card_form))
  end

  defp return_path("index", _card), do: ~p"/cards/manage"
  defp return_path("show", card), do: ~p"/cards/#{card.id}"

  defp card_side_form(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
      <!-- Basic Information -->
      <div class="space-y-4">
        <h4 class="font-medium text-gray-900">Basic Information</h4>
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:subname]} type="text" label="Subname" />
        <.input field={@form[:code]} type="text" label="Side Code" />
        <.input field={@form[:side_identifier]} type="text" label="Side Identifier" />
        <.input
          field={@form[:type]}
          type="select"
          label="Type"
          options={[
            {"Hero", "hero"},
            {"Alter Ego", "alter_ego"},
            {"Ally", "ally"},
            {"Event", "event"},
            {"Resource", "resource"},
            {"Support", "support"},
            {"Upgrade", "upgrade"},
            {"Villain", "villain"},
            {"Main Scheme", "main_scheme"},
            {"Side Scheme", "side_scheme"},
            {"Minion", "minion"},
            {"Attachment", "attachment"},
            {"Treachery", "treachery"},
            {"Obligation", "obligation"},
            {"Environment", "environment"}
          ]}
        />
        <.input
          field={@form[:ownership]}
          type="select"
          label="Ownership"
          prompt="—"
          options={[
            {"Player", "player"},
            {"Basic", "basic"},
            {"Pool", "pool"},
            {"Hero", "hero"},
            {"Encounter", "encounter"},
            {"Campaign", "campaign"}
          ]}
        />
        <.input
          field={@form[:aspect]}
          type="select"
          label="Aspect"
          prompt="—"
          options={[
            {"Aggression", "aggression"},
            {"Justice", "justice"},
            {"Leadership", "leadership"},
            {"Protection", "protection"}
          ]}
        />
        <.input field={@form[:cost]} type="number" label="Cost" />
        <.input field={@form[:text]} type="textarea" label="Text" />
        <.input
          name={@form.name <> "[traits_string]"}
          type="text"
          label="Traits (comma-separated)"
          value={
            case @form[:traits].value do
              nil -> ""
              [] -> ""
              list when is_list(list) -> Enum.join(list, ", ")
              string when is_binary(string) -> string
              _ -> ""
            end
          }
        />
      </div>

      <!-- Stats and Details -->
      <div class="space-y-4">
        <h4 class="font-medium text-gray-900">Stats & Details</h4>

        <!-- Combat Stats (stat value only; star/scaling/consequential come from sync) -->
        <div class="grid grid-cols-3 gap-2">
          <.input
            field={@form[:attack]}
            type="number"
            label="Attack"
            value={stat_value(@form[:attack].value)}
          />
          <.input
            field={@form[:thwart]}
            type="number"
            label="Thwart"
            value={stat_value(@form[:thwart].value)}
          />
          <.input
            field={@form[:defense]}
            type="number"
            label="Defense"
            value={stat_value(@form[:defense].value)}
          />
        </div>
        <.input
          field={@form[:health]}
          type="number"
          label="Health"
          value={stat_value(@form[:health].value)}
        />

        <!-- Hero Fields -->
        <div class="grid grid-cols-2 gap-2">
          <.input field={@form[:hand_size]} type="number" label="Hand Size" />
          <.input
            field={@form[:recover]}
            type="number"
            label="Recover"
            value={stat_value(@form[:recover].value)}
          />
        </div>

        <!-- Villain/Scheme Fields -->
        <.input field={@form[:stage]} type="number" label="Stage" />
        <div class="grid grid-cols-2 gap-2">
          <.input
            field={@form[:base_threat]}
            type="number"
            label="Base Threat"
            value={stat_value(@form[:base_threat].value)}
          />
          <.input
            field={@form[:escalation_threat]}
            type="number"
            label="Escalation Threat"
            value={stat_value(@form[:escalation_threat].value)}
          />
          <.input
            field={@form[:max_threat]}
            type="number"
            label="Max Threat"
            value={stat_value(@form[:max_threat].value)}
          />
        </div>

        <!-- Icons -->
        <div class="space-y-2">
          <label class="text-sm font-medium">Icons</label>
          <div class="grid grid-cols-2 gap-2">
            <.input field={@form[:acceleration_icon]} type="checkbox" label="Acceleration" />
            <.input field={@form[:amplify_icon]} type="checkbox" label="Amplify" />
            <.input field={@form[:crisis_icon]} type="checkbox" label="Crisis" />
            <.input field={@form[:hazard_icon]} type="checkbox" label="Hazard" />
            <.input field={@form[:boost_star]} type="checkbox" label="Boost Star" />
          </div>
        </div>

        <!-- Resources -->
        <div class="space-y-2">
          <label class="text-sm font-medium">Resource Icons</label>
          <div class="grid grid-cols-2 gap-2">
            <.input field={@form[:resource_energy_count]} type="number" label="Energy" />
            <.input field={@form[:resource_physical_count]} type="number" label="Physical" />
            <.input field={@form[:resource_mental_count]} type="number" label="Mental" />
            <.input field={@form[:resource_wild_count]} type="number" label="Wild" />
          </div>
        </div>

        <!-- Other Fields -->
        <.input field={@form[:boost]} type="number" label="Boost" />
        <.input field={@form[:image_url]} type="text" label="Image URL" />
      </div>
    </div>
    """
  end
end
