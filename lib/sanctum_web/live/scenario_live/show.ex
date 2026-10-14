defmodule SanctumWeb.ScenarioLive.Show do
  @moduledoc """
  Public scenario detail: villain art, name, villain set, modular sets and author.
  """
  use SanctumWeb, :live_view

  import SanctumWeb.Components.ScenarioCards

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:scenarios}>
      <!-- first-load skeleton -->
      <div :if={@scenario == nil}>
        <div class="mb-6 h-9 w-1/2 max-w-md animate-pulse bg-base-300"></div>
        <.detail_skeleton />
      </div>

      <div :if={@scenario != nil}>
        <.header>
          {@scenario.name}
          <:actions>
            <%!-- TODO(step C): navigate={~p"/scenarios/#{@scenario.id}/build"} --%>
            <.button
              :if={@view.mine}
              id="scenario-build"
              variant="primary"
              disabled
              title="Coming soon"
            >
              <.icon name="hero-wrench-screwdriver" /> Build
            </.button>
            <.back_button fallback={~p"/"} />
          </:actions>
        </.header>

        <div class="space-y-5">
          <.panel class="relative flex flex-col gap-5 overflow-hidden p-4 sm:flex-row sm:items-start">
            <div
              class="h-[330px] w-[236px] flex-none self-center border-2 border-neutral shadow-comic sm:self-start"
              style="transform:rotate(-1.5deg);"
            >
              <.mc_card
                name={@view.villain_name}
                aspect="encounter"
                image_url={@view.villain_image}
                size="lg"
                show_cost={false}
              />
            </div>

            <div class="flex min-w-0 flex-1 flex-col">
              <div
                id="scenario-villain-set"
                class="font-ibm-mono text-xs uppercase tracking-[0.25em] text-primary"
              >
                Scenario · {@view.villain_set_name}
              </div>
              <h1 class="mt-1.5 font-anton text-4xl uppercase leading-[0.9] [text-wrap:balance] sm:text-5xl sm:leading-[0.88]">
                {@scenario.name}
              </h1>
              <div :if={@view.author} id="scenario-author" class="mt-4 flex items-center gap-2">
                <.official_badge :if={@view.author.official?} />
                <%= if !@view.author.official? do %>
                  <.avatar name={@view.author.name} url={@view.author.avatar} size="md" />
                  <span class="font-barlow-condensed text-sm font-bold text-primary">
                    {@view.author.name}
                  </span>
                <% end %>
              </div>
            </div>
          </.panel>

          <.panel id="scenario-modular-sets" class="p-4">
            <h2 class="font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/50">
              Modular Sets
            </h2>
            <div
              :if={@view.modular_sets == []}
              class="mt-3 font-barlow text-sm italic text-base-content/45"
            >
              No modular sets.
            </div>
            <div :if={@view.modular_sets != []} class="mt-3 flex flex-wrap gap-2">
              <span
                :for={name <- @view.modular_sets}
                class="border-2 border-neutral bg-base-200 px-2 py-1 font-barlow-condensed text-sm font-bold uppercase tracking-[0.06em]"
              >
                {name}
              </span>
            </div>
          </.panel>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Scenario")
      |> assign(:scenario, nil)
      |> assign(:view, nil)

    actor = socket.assigns[:current_user]

    socket =
      if connected?(socket),
        do: start_async(socket, :load_scenario, fn -> load_scenario(id, actor) end),
        else: socket

    {:ok, socket}
  end

  @impl true
  def handle_async(:load_scenario, {:ok, {:ok, data}}, socket) do
    {:noreply,
     socket
     |> assign(:page_title, data.scenario.name)
     |> assign(:scenario, data.scenario)
     |> assign(:view, data.view)}
  end

  # TODO(step B): navigate to ~p"/scenarios" instead.
  def handle_async(:load_scenario, {:ok, :not_found}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Scenario not found.")
     |> push_navigate(to: ~p"/")}
  end

  def handle_async(:load_scenario, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Couldn’t load scenario: #{inspect(reason)}")
     |> push_navigate(to: ~p"/")}
  end

  # `:not_found` covers an unknown or invalid id.
  defp load_scenario(id, actor) do
    case Sanctum.Games.get_scenario(id,
           actor: actor,
           load: [
             :mine,
             :official,
             :owner,
             :villain_set,
             :modular_sets,
             villains: [:primary_side]
           ]
         ) do
      {:ok, s} -> {:ok, %{scenario: s, view: view(s)}}
      {:error, _} -> :not_found
    end
  end

  defp view(s) do
    first_villain =
      s.villains
      |> Enum.filter(& &1.primary_side)
      |> Enum.sort_by(&{&1.primary_side.stage || 999, &1.code})
      |> List.first()

    %{
      villain_image: villain_image(s),
      villain_name:
        (first_villain && first_villain.primary_side.name) ||
          (s.villain_set && s.villain_set.name),
      villain_set_name: s.villain_set && s.villain_set.name,
      modular_sets:
        s.modular_sets
        |> Enum.sort_by(&String.downcase(&1.name || &1.code))
        |> Enum.map(&(&1.name || &1.code)),
      author: author(s),
      # :mine loads nil for a nil actor.
      mine: s.mine == true
    }
  end
end
