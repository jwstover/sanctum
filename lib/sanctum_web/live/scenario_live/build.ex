defmodule SanctumWeb.ScenarioLive.Build do
  @moduledoc """
  Owner-only scenario builder: rename and description (both autosave), toggle modular sets
  (persisted immediately, no Save step) and delete. Non-owners and official
  scenarios are sent to the detail page.
  """

  use SanctumWeb, :live_view

  require Ash.Query

  import SanctumWeb.Components.ScenarioCards

  alias Sanctum.Games

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Games.get_scenario(id,
           actor: socket.assigns.current_user,
           load: [:mine, :modular_sets, :villain_set, villains: [:primary_side]]
         ) do
      {:ok, %{mine: true} = scenario} ->
        {:ok, seed(socket, scenario)}

      {:ok, scenario} ->
        {:ok,
         socket
         |> put_flash(:error, "Only the owner can build this scenario.")
         |> push_navigate(to: ~p"/scenarios/#{scenario.id}")}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Scenario not found.")
         |> push_navigate(to: ~p"/scenarios")}
    end
  end

  defp seed(socket, scenario) do
    groups = load_modular_groups()

    socket
    |> assign(:scenario, scenario)
    |> assign(:page_title, "Build · #{scenario.name}")
    |> assign(:description_draft, scenario.description_md || "")
    |> assign(:villain_image, villain_image(scenario))
    |> assign(:villain_name, villain_name(scenario))
    |> assign(
      :villain_set_name,
      scenario.villain_set && (scenario.villain_set.name || scenario.villain_set.code)
    )
    |> assign(:selected, MapSet.new(scenario.modular_sets, & &1.id))
    |> assign(:groups, groups)
    |> assign(:set_ids, groups |> Enum.flat_map(& &1.sets) |> MapSet.new(& &1.id))
  end

  defp load_modular_groups do
    Sanctum.Catalog.CardSet
    |> Ash.Query.filter(set_type == :modular)
    |> Ash.Query.load(pack: [:wave])
    |> Ash.read!(authorize?: false)
    |> Enum.group_by(fn
      %{pack: %{wave: %{number: n, name: name}}} -> {{0, n}, name}
      _ -> {{1, 0}, "Other"}
    end)
    |> Enum.sort_by(fn {{key, _label}, _sets} -> key end)
    |> Enum.map(fn {{_key, label}, sets} ->
      %{
        label: label,
        sets:
          sets
          |> Enum.sort_by(
            &{(&1.pack && &1.pack.position) || 9999, String.downcase(&1.name || &1.code)}
          )
          |> Enum.map(&%{id: &1.id, name: &1.name || &1.code})
      }
    end)
  end

  @impl true
  def handle_event("toggle_set", %{"id" => id}, socket) do
    %{scenario: scenario, selected: selected, set_ids: set_ids, current_user: user} =
      socket.assigns

    if MapSet.member?(set_ids, id) do
      new =
        if MapSet.member?(selected, id),
          do: MapSet.delete(selected, id),
          else: MapSet.put(selected, id)

      case Games.set_scenario_modular_sets(scenario, %{modular_sets: MapSet.to_list(new)},
             actor: user
           ) do
        {:ok, _} -> {:noreply, assign(socket, :selected, new)}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Couldn’t update the modular sets.")}
      end
    else
      {:noreply, socket}
    end
  end

  # Autosave like the deck builder: debounced input, Enter flushes. Blank or
  # unchanged names are no-ops.
  def handle_event("rename", params, socket) do
    name = params["name"] || ""
    scenario = socket.assigns.scenario

    if String.trim(name) in ["", scenario.name] do
      {:noreply, socket}
    else
      updated =
        Games.rename_scenario!(scenario, %{name: name}, actor: socket.assigns.current_user)

      {:noreply,
       socket
       |> assign(:scenario, %{scenario | name: updated.name})
       |> assign(:page_title, "Build · #{updated.name}")}
    end
  end

  # Autosave: the textarea debounces client-side, so each event is a settled pause.
  def handle_event("description_change", %{"description" => draft}, socket) do
    %{scenario: scenario, current_user: user} = socket.assigns

    if draft == (scenario.description_md || "") do
      {:noreply, assign(socket, :description_draft, draft)}
    else
      case Games.set_scenario_description(scenario, %{description_md: draft}, actor: user) do
        {:ok, updated} ->
          {:noreply,
           socket
           |> assign(:scenario, %{scenario | description_md: updated.description_md})
           |> assign(:description_draft, draft)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Couldn’t save the description.")}
      end
    end
  end

  def handle_event("delete", _params, socket) do
    Games.destroy_scenario!(socket.assigns.scenario, actor: socket.assigns.current_user)

    {:noreply,
     socket
     |> put_flash(:info, "Scenario deleted.")
     |> push_navigate(to: ~p"/scenarios")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:scenarios}>
      <.header>
        {@scenario.name}
        <:actions>
          <.button id="scenario-view" navigate={~p"/scenarios/#{@scenario.id}"}>View</.button>
          <.confirm_button
            id="confirm-delete-scenario"
            message="Delete this scenario? This cannot be undone."
            confirm_label="Delete scenario"
            class="btn btn-error"
            phx-click="delete"
          >
            <.icon name="hero-trash" class="size-4" /> Delete
          </.confirm_button>
        </:actions>
      </.header>

      <.panel class="mb-6 flex items-start gap-4 p-4">
        <div class="w-24 flex-none">
          <.mc_card
            name={@villain_name || @villain_set_name}
            aspect="encounter"
            image_url={@villain_image}
            size="md"
            show_cost={false}
          />
        </div>
        <div class="min-w-0 flex-1">
          <div class="mb-2 font-anton text-xs uppercase tracking-[0.06em] text-base-content/45">
            Scenario · {@villain_set_name}
          </div>
          <form id="rename-form" phx-change="rename" phx-submit="rename">
            <label
              for="scenario-name"
              class="mb-1.5 block font-anton text-xs uppercase tracking-[0.06em] text-base-content/45"
            >
              Name
            </label>
            <input
              id="scenario-name"
              type="text"
              name="name"
              value={@scenario.name}
              phx-debounce="600"
              autocomplete="off"
              class="w-full border-[2.5px] border-line bg-black px-3.5 py-2.5 font-anton text-lg uppercase tracking-[0.04em] text-base-content outline-none focus:border-primary"
            />
          </form>
        </div>
      </.panel>

      <section id="scenario-description" class="mb-6">
        <form id="description-form" phx-change="description_change" phx-submit="description_change">
          <label
            for="scenario-description-input"
            class="mb-1.5 block font-anton text-xs uppercase tracking-[0.06em] text-base-content/45"
          >
            Description
          </label>
          <textarea
            id="scenario-description-input"
            name="description"
            phx-debounce="600"
            rows="6"
            placeholder="How this scenario plays, why these modular sets, setup notes… Markdown supported."
            class="block w-full border-[2.5px] border-line bg-black px-3.5 py-3 font-ibm-mono text-sm leading-relaxed text-base-content outline-none focus:border-primary"
          >{@description_draft}</textarea>
        </form>
      </section>

      <section id="modular-sets" class="pb-6">
        <h2 class="mb-3 font-anton text-xl uppercase tracking-[0.05em]">
          Modular Sets
          <span id="modular-count" class="text-base text-base-content/45">
            {MapSet.size(@selected)} selected
          </span>
        </h2>
        <div :for={group <- @groups} class="mb-4">
          <h3 class="mb-2 font-anton text-sm uppercase tracking-[0.08em] text-base-content/45">
            {group.label}
          </h3>
          <div class="flex flex-wrap gap-1.5">
            <button
              :for={set <- group.sets}
              id={"modular-set-#{set.id}"}
              type="button"
              phx-click="toggle_set"
              phx-value-id={set.id}
              aria-pressed={to_string(MapSet.member?(@selected, set.id))}
              class={[
                "cursor-pointer border-2 px-2 py-1 font-barlow-condensed text-sm font-bold uppercase tracking-[0.06em]",
                (MapSet.member?(@selected, set.id) && "border-primary bg-primary text-primary-content") ||
                  "border-neutral bg-base-200"
              ]}
            >
              {set.name}
            </button>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
