defmodule SanctumWeb.ScenarioLive.New do
  @moduledoc """
  Villain-set picker for building a scenario: a card-art grid and a name
  filter. Picking a set creates a user scenario at once (named
  "<set> Scenario") and goes to the builder.

  Lists villain CardSets, not `Villains.Villain` rows: Loki's forms and the
  Sinister Six are several Villain rows but one set.
  """

  use SanctumWeb, :live_view

  require Ash.Query

  import SanctumWeb.Components.ScenarioCards

  alias Sanctum.Games

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Scenario")
     |> assign(:villain_sets, load_villain_sets())
     |> assign(:filter, "")}
  end

  @impl true
  def handle_event("filter", %{"q" => q}, socket) do
    {:noreply, assign(socket, :filter, q)}
  end

  def handle_event("select_set", %{"id" => id}, socket) do
    %{villain_sets: sets, current_user: user} = socket.assigns

    case Enum.find(sets, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      set ->
        case Games.build_scenario(%{villain_set_id: set.id}, actor: user) do
          {:ok, scenario} ->
            {:noreply, push_navigate(socket, to: ~p"/scenarios/#{scenario.id}/build")}

          {:error, _error} ->
            {:noreply, put_flash(socket, :error, "Could not create the scenario")}
        end
    end
  end

  defp load_villain_sets do
    sets =
      Sanctum.Catalog.CardSet
      |> Ash.Query.filter(set_type == :villain)
      |> Ash.read!(authorize?: false)

    codes = Enum.map(sets, & &1.code)

    villains_by_set =
      Sanctum.Games.Card
      |> Ash.Query.filter(set in ^codes and primary_side.type == :villain)
      |> Ash.Query.load(:primary_side)
      |> Ash.read!(authorize?: false)
      |> Enum.group_by(& &1.set)

    sets
    |> Enum.map(fn set ->
      set_name = set.name || set.code
      src = %{villains: Map.get(villains_by_set, set.code, []), villain_set: set}

      %{
        id: set.id,
        set_name: set_name,
        villain_name: villain_name(src) || set_name,
        image_url: villain_image(src)
      }
    end)
    |> Enum.sort_by(&String.downcase(&1.set_name))
  end

  defp visible?(set, filter) do
    filter = filter |> String.trim() |> String.downcase()

    filter == "" or
      String.contains?(String.downcase(set.villain_name), filter) or
      String.contains?(String.downcase(set.set_name), filter)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:scenarios}>
      <.header>
        New Scenario
      </.header>

      <form id="villain-filter" phx-change="filter" class="mb-4" onsubmit="return false">
        <.input
          type="text"
          name="q"
          value={@filter}
          placeholder="Filter villains…"
          autocomplete="off"
          phx-debounce="150"
        />
      </form>

      <div class="grid grid-cols-[repeat(auto-fill,minmax(110px,1fr))] gap-2.5 pb-6">
        <div :for={set <- @villain_sets} :if={visible?(set, @filter)} class="flex flex-col gap-1">
          <button
            id={"villain-set-#{set.id}"}
            type="button"
            phx-click="select_set"
            phx-value-id={set.id}
            class="aspect-[63/88] border-2 border-neutral text-left shadow-comic-sm transition-transform hover:-translate-y-0.5 hover:outline hover:outline-[3px] hover:outline-primary"
          >
            <.mc_card
              name={set.villain_name}
              aspect="encounter"
              image_url={set.image_url}
              size="md"
              show_cost={false}
            />
          </button>
          <span class="truncate font-barlow-condensed text-xs uppercase text-base-content/60">
            {set.set_name}
          </span>
        </div>
      </div>
      <p
        :if={Enum.all?(@villain_sets, &(not visible?(&1, @filter)))}
        class="py-6 text-center text-base-content/45"
      >
        No villains match.
      </p>
    </Layouts.app>
    """
  end
end
