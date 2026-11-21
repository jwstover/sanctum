defmodule SanctumWeb.ScenarioLive.New do
  @moduledoc """
  Step 1 of building a scenario: a card-art grid with search and sort. Picking
  a tile only selects it; "Continue to modular sets" creates the user scenario
  (named "<set> Scenario") and goes to the builder.

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
     |> assign(:filter, "")
     |> assign(:sort, :az)
     |> assign(:picked, nil)}
  end

  @impl true
  def handle_event("filter", %{"q" => q}, socket) do
    {:noreply, assign(socket, :filter, q)}
  end

  def handle_event("sort", %{"by" => by}, socket) when by in ["az", "new"] do
    {:noreply, assign(socket, :sort, String.to_existing_atom(by))}
  end

  def handle_event("select_set", %{"id" => id}, socket) do
    picked = if Enum.any?(socket.assigns.villain_sets, &(&1.id == id)), do: id
    picked = if picked == socket.assigns.picked, do: nil, else: picked

    {:noreply, assign(socket, :picked, picked)}
  end

  def handle_event("continue", _params, socket) do
    %{villain_sets: sets, picked: picked, current_user: user} = socket.assigns

    with %{} = set <- Enum.find(sets, &(&1.id == picked)),
         {:ok, scenario} <- Games.build_scenario(%{villain_set_id: set.id}, actor: user) do
      {:noreply, push_navigate(socket, to: ~p"/scenarios/#{scenario.id}/build")}
    else
      nil -> {:noreply, socket}
      {:error, _error} -> {:noreply, put_flash(socket, :error, "Could not create the scenario")}
    end
  end

  defp load_villain_sets do
    sets =
      Sanctum.Catalog.CardSet
      |> Ash.Query.filter(set_type == :villain)
      |> Ash.Query.load(:pack)
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
        image_url: villain_image(src),
        position: (set.pack && set.pack.position) || 0
      }
    end)
    |> Enum.sort_by(&String.downcase(&1.set_name))
  end

  defp sorted(sets, :az), do: sets
  defp sorted(sets, :new), do: Enum.sort_by(sets, & &1.position, :desc)

  defp villain_line(set),
    do: if(set.villain_name != set.set_name, do: "Villain: #{set.villain_name}")

  defp visible?(set, filter) do
    filter = filter |> String.trim() |> String.downcase()

    filter == "" or
      String.contains?(String.downcase(set.villain_name), filter) or
      String.contains?(String.downcase(set.set_name), filter)
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(
        :visible,
        assigns.villain_sets |> Enum.filter(&visible?(&1, assigns.filter)) |> sorted(assigns.sort)
      )
      |> assign(:pick, Enum.find(assigns.villain_sets, &(&1.id == assigns.picked)))

    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:scenarios}>
      <div class="mb-1 flex items-center gap-2 font-barlow-condensed text-sm uppercase tracking-[0.14em] text-base-content/50">
        <.link navigate={~p"/scenarios"}>Scenarios</.link>
        <span aria-hidden="true">/</span>
        <span class="text-secondary">New scenario</span>
      </div>
      <h1 class="font-anton text-4xl uppercase leading-none sm:text-5xl">Choose a villain</h1>

      <div class="mb-2 mt-5 flex flex-col gap-3 sm:flex-row sm:items-center">
        <form id="villain-filter" phx-change="filter" class="flex-1" onsubmit="return false">
          <.input
            type="search"
            name="q"
            value={@filter}
            placeholder="Search by scenario or villain — e.g. Collector, Sinister Six"
            autocomplete="off"
            phx-debounce="150"
          />
        </form>
        <div role="group" aria-label="Sort" class="flex">
          <button
            :for={{key, label} <- [az: "A–Z", new: "Newest"]}
            id={"sort-#{key}"}
            type="button"
            phx-click="sort"
            phx-value-by={key}
            aria-pressed={to_string(@sort == key)}
            class={[
              "h-12 border px-4 font-barlow-condensed text-sm font-semibold uppercase tracking-[0.1em]",
              (@sort == key && "border-base-content bg-base-content text-base-100") ||
                "border-line bg-base-200 text-base-content/70"
            ]}
          >
            {label}
          </button>
        </div>
      </div>
      <div id="villain-count" class="mb-5 text-sm text-base-content/50">
        {length(@visible)} of {length(@villain_sets)} villains
      </div>

      <div class="grid grid-cols-2 gap-4 pb-32 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-6">
        <button
          :for={set <- @visible}
          id={"villain-set-#{set.id}"}
          type="button"
          phx-click="select_set"
          phx-value-id={set.id}
          aria-pressed={to_string(@picked == set.id)}
          class={[
            "relative flex flex-col border-2 bg-base-200 text-left shadow-comic-sm hover:border-secondary",
            (@picked == set.id && "border-primary outline outline-2 outline-primary") ||
              "border-neutral"
          ]}
        >
          <div class="aspect-[63/88] w-full">
            <.mc_card
              name={set.villain_name}
              aspect="encounter"
              image_url={set.image_url}
              size="md"
              show_cost={false}
            />
          </div>
          <span
            :if={@picked == set.id}
            class="absolute right-2 top-2 flex size-7 items-center justify-center bg-primary text-primary-content shadow-comic-sm"
          >
            <.icon name="hero-check" class="size-4" />
          </span>
          <span class="flex min-h-16 flex-col gap-1.5 p-3">
            <span class="font-anton text-lg uppercase leading-none">{set.set_name}</span>
            <span class="text-xs text-base-content/50">{villain_line(set)}</span>
          </span>
        </button>
      </div>
      <p :if={@visible == []} class="py-6 text-base-content/45">
        No villains match “{@filter}”.
      </p>

      <div class="fixed inset-x-0 bottom-0 z-10 flex items-center gap-4 border-t border-line bg-base-200 px-4 py-3 sm:px-10 lg:left-[232px]">
        <%= if @pick do %>
          <div class="min-w-0 flex-1">
            <div class="font-barlow-condensed text-xs uppercase tracking-[0.14em] text-base-content/50">
              Selected villain
            </div>
            <div id="picked-villain" class="truncate font-anton text-xl uppercase">
              {@pick.set_name}
              <span class="font-barlow text-sm normal-case text-base-content/50">
                {villain_line(@pick)}
              </span>
            </div>
          </div>
          <.button id="continue-scenario" variant="primary" phx-click="continue">
            Continue to modular sets <.icon name="hero-arrow-right" class="size-4" />
          </.button>
        <% else %>
          <span class="flex-1 text-base-content/50">Pick a villain to continue.</span>
          <.button id="continue-scenario" disabled>Continue to modular sets</.button>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
