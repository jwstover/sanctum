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
    |> assign(:query, "")
    |> assign(:selected_only, false)
    |> assign(:hide_campaign, false)
    |> assign(:wave, :all)
    |> assign(:closed, MapSet.new())
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
          |> Enum.map(&%{id: &1.id, name: &1.name || &1.code, campaign?: campaign?(&1)})
      }
    end)
  end

  defp campaign?(set), do: String.contains?(set.name || "", "Campaign")

  # Groups narrowed by the search, "selected only" and "hide campaign" filters;
  # empty groups drop out. A search forces every wave open.
  defp visible_groups(assigns) do
    %{groups: groups, query: query, selected: selected, wave: wave} = assigns
    q = query |> String.trim() |> String.downcase()

    groups
    |> Enum.filter(&(wave == :all or &1.label == wave))
    |> Enum.map(fn group ->
      sets =
        Enum.filter(group.sets, fn set ->
          (q == "" or String.contains?(String.downcase(set.name), q)) and
            (not assigns.selected_only or MapSet.member?(selected, set.id)) and
            not (assigns.hide_campaign and set.campaign?)
        end)

      Map.put(group, :visible, sets)
    end)
    |> Enum.reject(&(&1.visible == []))
  end

  defp group_selected(group, selected),
    do: Enum.count(group.sets, &MapSet.member?(selected, &1.id))

  defp persist_selected(socket, new) do
    %{scenario: scenario, current_user: user} = socket.assigns

    case Games.set_scenario_modular_sets(scenario, %{modular_sets: MapSet.to_list(new)},
           actor: user
         ) do
      {:ok, _} -> {:noreply, assign(socket, :selected, new)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Couldn’t update the modular sets.")}
    end
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket), do: {:noreply, assign(socket, :query, q)}

  def handle_event("toggle_filter", %{"filter" => f}, socket)
      when f in ["selected_only", "hide_campaign"] do
    key = String.to_existing_atom(f)
    {:noreply, assign(socket, key, not socket.assigns[key])}
  end

  def handle_event("pick_wave", %{"wave" => "all"}, socket),
    do: {:noreply, assign(socket, :wave, :all)}

  def handle_event("pick_wave", %{"wave" => label}, socket),
    do: {:noreply, assign(socket, :wave, label)}

  def handle_event("toggle_wave", %{"wave" => label}, socket) do
    closed = socket.assigns.closed

    closed =
      if MapSet.member?(closed, label),
        do: MapSet.delete(closed, label),
        else: MapSet.put(closed, label)

    {:noreply, assign(socket, :closed, closed)}
  end

  def handle_event("reset_filters", _params, socket) do
    {:noreply, assign(socket, query: "", selected_only: false, hide_campaign: false, wave: :all)}
  end

  def handle_event("clear_sets", _params, socket), do: persist_selected(socket, MapSet.new())

  def handle_event("toggle_set", %{"id" => id}, socket) do
    %{selected: selected, set_ids: set_ids} = socket.assigns

    if MapSet.member?(set_ids, id) do
      new =
        if MapSet.member?(selected, id),
          do: MapSet.delete(selected, id),
          else: MapSet.put(selected, id)

      persist_selected(socket, new)
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
    assigns =
      assigns
      |> assign(:visible_groups, visible_groups(assigns))
      |> assign(:selected_sets, selected_sets(assigns))

    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:scenarios}>
      <div class="mb-1 flex items-center gap-2 font-barlow-condensed text-sm uppercase tracking-[0.14em] text-base-content/50">
        <.link navigate={~p"/scenarios"}>Scenarios</.link>
        <span aria-hidden="true">/</span>
        <span class="text-secondary">Build</span>
      </div>
      <form id="rename-form" phx-change="rename" phx-submit="rename" class="mb-6">
        <label for="scenario-name" class="sr-only">Scenario name</label>
        <input
          id="scenario-name"
          type="text"
          name="name"
          value={@scenario.name}
          phx-debounce="600"
          autocomplete="off"
          class="w-full border-0 border-b-2 border-dashed border-transparent bg-transparent p-0 pb-1 font-anton text-4xl uppercase leading-tight outline-none hover:border-line focus:border-primary sm:text-5xl"
        />
      </form>

      <div class="flex flex-col gap-8 lg:flex-row lg:items-start">
        <div class="min-w-0 flex-1 space-y-9">
          <section id="scenario-villain" aria-labelledby="villain-h">
            <h2 id="villain-h" class="mb-3 font-anton text-2xl uppercase tracking-[0.02em]">
              Villain
            </h2>
            <.panel class="flex items-center gap-5 p-4">
              <div class="w-16 flex-none">
                <.mc_card
                  name={@villain_name || @villain_set_name}
                  aspect="encounter"
                  image_url={@villain_image}
                  size="md"
                  show_cost={false}
                />
              </div>
              <div class="min-w-0 flex-1">
                <div class="font-anton text-2xl uppercase leading-none">{@villain_set_name}</div>
                <div
                  :if={@villain_name != @villain_set_name}
                  class="mt-1.5 text-sm text-base-content/50"
                >
                  {@villain_name}
                </div>
              </div>
            </.panel>
          </section>

          <section id="scenario-description">
            <form
              id="description-form"
              phx-change="description_change"
              phx-submit="description_change"
            >
              <label
                for="scenario-description-input"
                class="mb-3 block font-anton text-2xl uppercase tracking-[0.02em]"
              >
                Description
              </label>
              <textarea
                id="scenario-description-input"
                name="description"
                phx-debounce="600"
                rows="6"
                placeholder="How this scenario plays, why these modular sets, setup notes… Markdown supported."
                class="block w-full border border-line bg-black px-3.5 py-3 font-ibm-mono text-sm leading-relaxed text-base-content outline-none focus:border-primary"
              >{@description_draft}</textarea>
            </form>
          </section>

          <section id="modular-sets" aria-labelledby="sets-h" class="pb-6">
            <h2 id="sets-h" class="font-anton text-2xl uppercase tracking-[0.02em]">Modular sets</h2>
            <p class="mb-4 mt-2 text-base-content/60">
              Pick the encounter sets shuffled into the villain deck. Most scenarios use one or two.
            </p>

            <div class="mb-5 border border-line bg-base-200">
              <div class="flex flex-wrap items-center gap-3 p-3.5">
                <form
                  id="set-search"
                  phx-change="search"
                  onsubmit="return false"
                  class="min-w-48 flex-1"
                >
                  <.input
                    type="search"
                    name="q"
                    value={@query}
                    placeholder="Search modular sets"
                    autocomplete="off"
                    phx-debounce="150"
                  />
                </form>
                <.filter_toggle id="filter-selected" filter="selected_only" on={@selected_only}>
                  Selected only
                </.filter_toggle>
                <.filter_toggle id="filter-campaign" filter="hide_campaign" on={@hide_campaign}>
                  Hide campaign sets
                </.filter_toggle>
              </div>
              <div
                role="tablist"
                aria-label="Filter by wave"
                class="flex items-center gap-1 overflow-x-auto border-t border-line px-2.5"
              >
                <.wave_pill label="All waves" wave="all" on={@wave == :all} count={0} />
                <.wave_pill
                  :for={g <- @groups}
                  label={g.label}
                  wave={g.label}
                  on={@wave == g.label}
                  count={group_selected(g, @selected)}
                />
              </div>
            </div>

            <div class="space-y-5">
              <div :for={group <- @visible_groups} id={"wave-#{group.label}"}>
                <% open = @query != "" or not MapSet.member?(@closed, group.label) %>
                <button
                  type="button"
                  phx-click="toggle_wave"
                  phx-value-wave={group.label}
                  aria-expanded={to_string(open)}
                  class="mb-2 flex h-11 w-full cursor-pointer items-center gap-3 text-left"
                >
                  <.icon
                    name="hero-chevron-down"
                    class={"size-4 text-base-content/50 #{unless open, do: "-rotate-90"}"}
                  />
                  <span class="font-anton text-xl uppercase tracking-[0.04em]">{group.label}</span>
                  <span class="text-sm text-base-content/50">{length(group.visible)} sets</span>
                  <span
                    :if={group_selected(group, @selected) > 0}
                    class="bg-primary px-1.5 py-0.5 font-barlow-condensed text-xs font-bold text-primary-content"
                  >
                    {group_selected(group, @selected)} selected
                  </span>
                  <span class="h-px flex-1 bg-line"></span>
                </button>
                <div :if={open} class="flex flex-wrap gap-2 pl-7">
                  <button
                    :for={set <- group.visible}
                    id={"modular-set-#{set.id}"}
                    type="button"
                    phx-click="toggle_set"
                    phx-value-id={set.id}
                    aria-pressed={to_string(MapSet.member?(@selected, set.id))}
                    class={[
                      "flex cursor-pointer items-center gap-1.5 border-2 px-2.5 py-1.5 font-barlow-condensed text-sm font-bold uppercase tracking-[0.06em]",
                      (MapSet.member?(@selected, set.id) &&
                         "border-primary bg-primary text-primary-content") ||
                        "border-neutral bg-base-200"
                    ]}
                  >
                    <.icon
                      name={(MapSet.member?(@selected, set.id) && "hero-check") || "hero-plus"}
                      class="size-3.5"
                    />
                    {set.name}
                  </button>
                </div>
              </div>
              <div :if={@visible_groups == []} class="border border-dashed border-line p-8">
                <div class="font-anton text-2xl uppercase">No sets match “{@query}”</div>
                <p class="my-2 text-base-content/60">Try a shorter search, or clear the filters.</p>
                <.button id="reset-filters" phx-click="reset_filters">Clear filters</.button>
              </div>
            </div>
          </section>
        </div>

        <aside aria-label="Scenario summary" class="w-full flex-none lg:sticky lg:top-4 lg:w-[360px]">
          <.panel class="bg-base-300 p-0">
            <div class="space-y-2 px-5 pb-3.5 pt-5">
              <div class="font-barlow-condensed text-xs uppercase tracking-[0.14em] text-base-content/50">
                Villain
              </div>
              <div class="flex h-10 items-center gap-2.5 bg-black px-3 font-barlow-condensed text-base font-bold uppercase tracking-[0.06em]">
                <span class="size-2 bg-error"></span>{@villain_set_name}
              </div>
            </div>
            <div class="flex items-center justify-between px-5 py-2">
              <div
                id="modular-count"
                class="font-barlow-condensed text-xs uppercase tracking-[0.14em] text-base-content/50"
              >
                Modular sets · {MapSet.size(@selected)} selected
              </div>
              <button
                :if={MapSet.size(@selected) > 0}
                id="clear-sets"
                type="button"
                phx-click="clear_sets"
                class="cursor-pointer font-barlow-condensed text-xs font-bold uppercase tracking-[0.1em] text-primary"
              >
                Clear all
              </button>
            </div>
            <ul id="selected-sets" class="max-h-80 space-y-1.5 overflow-y-auto px-5">
              <li
                :for={set <- @selected_sets}
                class="flex h-11 items-center gap-2.5 border-l-[3px] border-primary bg-black pl-3 pr-1.5"
              >
                <div class="min-w-0 flex-1">
                  <div class="truncate font-barlow-condensed text-[15px] font-bold uppercase tracking-[0.05em]">
                    {set.name}
                  </div>
                  <div class="text-xs text-base-content/50">{set.wave}</div>
                </div>
                <button
                  type="button"
                  phx-click="toggle_set"
                  phx-value-id={set.id}
                  aria-label={"Remove #{set.name}"}
                  class="flex size-8 cursor-pointer items-center justify-center text-base-content/50 hover:text-base-content"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </li>
              <li
                :if={@selected_sets == []}
                class="border border-dashed border-line px-3.5 py-4 text-sm text-base-content/60"
              >
                No modular sets yet. Pick one or more from the list — they’ll collect here.
              </li>
            </ul>
            <div class="mt-4 space-y-2 border-t border-line p-5">
              <.button
                id="scenario-view"
                variant="primary"
                class="w-full"
                navigate={~p"/scenarios/#{@scenario.id}"}
              >
                <.icon name="hero-check" class="size-4" /> Done
              </.button>
              <div class="flex h-7 items-center justify-center gap-2 font-barlow-condensed text-xs uppercase tracking-[0.1em] text-base-content/50">
                <span class="size-[7px] rounded-full bg-success"></span>All changes saved
              </div>
              <.confirm_button
                id="confirm-delete-scenario"
                message="Delete this scenario? This cannot be undone."
                confirm_label="Delete scenario"
                class="btn btn-error w-full"
                phx-click="delete"
              >
                <.icon name="hero-trash" class="size-4" /> Delete
              </.confirm_button>
            </div>
          </.panel>
        </aside>
      </div>
    </Layouts.app>
    """
  end

  defp selected_sets(%{groups: groups, selected: selected}) do
    for group <- groups, set <- group.sets, MapSet.member?(selected, set.id) do
      %{id: set.id, name: set.name, wave: group.label}
    end
  end

  attr :id, :string, required: true
  attr :filter, :string, required: true
  attr :on, :boolean, required: true
  slot :inner_block, required: true

  defp filter_toggle(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click="toggle_filter"
      phx-value-filter={@filter}
      aria-pressed={to_string(@on)}
      class={[
        "flex h-11 cursor-pointer items-center gap-2 border px-3.5 font-barlow-condensed text-sm font-semibold uppercase tracking-[0.08em]",
        (@on && "border-primary text-primary") || "border-line text-base-content/70"
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :label, :string, required: true
  attr :wave, :string, required: true
  attr :on, :boolean, required: true
  attr :count, :integer, required: true

  defp wave_pill(assigns) do
    ~H"""
    <button
      type="button"
      role="tab"
      phx-click="pick_wave"
      phx-value-wave={@wave}
      aria-selected={to_string(@on)}
      class={[
        "flex h-11 flex-none cursor-pointer items-center gap-1.5 border-b-2 px-3 font-barlow-condensed text-sm font-semibold uppercase tracking-[0.08em]",
        (@on && "border-primary text-base-content") || "border-transparent text-base-content/60"
      ]}
    >
      {@label}
      <span
        :if={@count > 0}
        class="min-w-[18px] bg-primary px-1 text-center text-xs font-bold text-primary-content"
      >
        {@count}
      </span>
    </button>
    """
  end
end
