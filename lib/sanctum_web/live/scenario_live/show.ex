defmodule SanctumWeb.ScenarioLive.Show do
  @moduledoc """
  Public scenario detail: villain art, name, villain set, description (markdown), modular sets and author.
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
        <div class="mb-1 flex items-center gap-2 font-barlow-condensed text-sm uppercase tracking-[0.14em] text-base-content/50">
          <.link navigate={~p"/scenarios"}>Scenarios</.link>
          <span aria-hidden="true">/</span>
          <span class="text-secondary">Scenario</span>
        </div>
        <header class="mb-6 flex flex-col gap-4 border-b border-line pb-5 sm:flex-row sm:items-end sm:justify-between">
          <div class="min-w-0">
            <h1 class="font-anton text-4xl uppercase leading-none [text-wrap:balance] sm:text-5xl">
              {@scenario.name}
            </h1>
            <div id="scenario-meta" class="mt-3 flex flex-wrap gap-2">
              <span class="meta-chip">
                <span class="size-2 bg-error"></span>Villain · {@view.villain_name}
              </span>
              <span class="meta-chip">
                {length(@view.modular_sets)} modular {if length(@view.modular_sets) == 1,
                  do: "set",
                  else: "sets"}
              </span>
              <span :if={@view.author} class="meta-chip">By {@view.author.name}</span>
              <span class="meta-chip">
                Updated {Calendar.strftime(@scenario.updated_at, "%b %-d, %Y")}
              </span>
            </div>
          </div>
          <div class="flex flex-none items-center gap-3">
            <.button
              :if={@view.mine}
              id="scenario-build"
              variant="primary"
              navigate={~p"/scenarios/#{@scenario.id}/build"}
            >
              <.icon name="hero-pencil-square" /> Edit
            </.button>
            <.back_button fallback={~p"/scenarios"} />
          </div>
        </header>

        <div class="space-y-5">
          <div class="grid items-start gap-5 lg:grid-cols-[1.4fr_1fr]">
            <div class="min-w-0 space-y-5">
              <section id="scenario-encounter-deck" aria-labelledby="deck-h">
                <h2 id="deck-h" class="mb-3 font-anton text-2xl uppercase tracking-[0.02em]">
                  Encounter deck
                </h2>
                <.panel class="flex flex-col gap-6 p-5 sm:flex-row">
                  <div class="w-[190px] flex-none self-center sm:self-start">
                    <div class="h-[266px] w-[190px] shadow-comic-sm">
                      <.mc_card
                        name={@view.villain_name}
                        aspect="encounter"
                        image_url={@view.villain_image}
                        size="lg"
                        show_cost={false}
                      />
                    </div>
                  </div>
                  <div class="min-w-0 flex-1 space-y-2">
                    <div id="scenario-villain-set" class="deck-row border-l-error">
                      <div class="flex-1">
                        <div class="font-barlow-condensed text-[17px] font-bold uppercase tracking-[0.05em]">
                          {@view.villain_set_name}
                        </div>
                        <div class="mt-1 text-xs text-base-content/50">Villain encounter set</div>
                      </div>
                      <span class="deck-tag">Villain</span>
                    </div>
                    <div
                      :if={@view.modular_sets == []}
                      class="font-barlow text-sm italic text-base-content/45"
                    >
                      No modular sets.
                    </div>
                    <div :for={ms <- @view.modular_sets} class="deck-row border-l-primary">
                      <div class="flex-1">
                        <div class="font-barlow-condensed text-[17px] font-bold uppercase tracking-[0.05em]">
                          {ms.name}
                        </div>
                        <div class="mt-1 text-xs text-base-content/50">Modular set</div>
                      </div>
                      <span class="deck-tag">Modular</span>
                    </div>
                  </div>
                </.panel>
              </section>

              <section
                :for={ms <- @view.modular_sets}
                id={"modular-set-#{ms.code}"}
                aria-labelledby={"modular-#{ms.code}-h"}
              >
                <h2
                  id={"modular-#{ms.code}-h"}
                  class="mb-3 font-anton text-2xl uppercase tracking-[0.02em]"
                >
                  {ms.name}
                </h2>
                <.panel class="flex flex-col gap-6 p-5 sm:flex-row">
                  <div class="flex-none self-center sm:self-start">
                    <.card_fan cards={ms.fan} />
                  </div>
                  <div class="min-w-0 flex-1 space-y-3">
                    <div class="deck-row border-l-primary">
                      <div class="flex-1">
                        <div class="font-barlow-condensed text-[17px] font-bold uppercase tracking-[0.05em]">
                          {ms.name}
                        </div>
                        <div class="mt-1 text-xs text-base-content/50">Modular set</div>
                      </div>
                      <span class="deck-tag">Modular</span>
                    </div>
                  </div>
                </.panel>
              </section>
            </div>

            <.panel
              :if={stats_present?(@view.overall_stats)}
              id="scenario-stats"
              class="min-w-0 p-4"
            >
              <div class="mb-3 font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/50">
                Encounter Stats
              </div>
              <.encounter_stats stats={@view.overall_stats} />
            </.panel>
          </div>

          <.panel :if={@view.description} id="scenario-description" class="min-w-0 p-4">
            <h2 class="font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/50">
              Description
            </h2>
            <div class="mt-3 space-y-4">
              <div :for={seg <- @view.description}>
                <div :if={seg.kind == :inline} class="deck-writeup">{seg.html}</div>
                <iframe
                  :if={seg.kind == :rich}
                  title="Scenario description"
                  sandbox=""
                  referrerpolicy="no-referrer"
                  loading="lazy"
                  class="deck-writeup-frame"
                  srcdoc={seg.srcdoc}
                ></iframe>
              </div>
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

  def handle_async(:load_scenario, {:ok, :not_found}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Scenario not found.")
     |> push_navigate(to: ~p"/scenarios")}
  end

  def handle_async(:load_scenario, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Couldn’t load scenario: #{inspect(reason)}")
     |> push_navigate(to: ~p"/scenarios")}
  end

  # `:not_found` covers an unknown or invalid id.
  defp load_scenario(id, actor) do
    case Sanctum.Games.get_scenario(id,
           actor: actor,
           load: [
             :mine,
             :official,
             :owner,
             villain_set: [cards: [:primary_side]],
             modular_sets: [cards: [:primary_side]],
             villains: [:primary_side]
           ]
         ) do
      {:ok, s} -> {:ok, %{scenario: s, view: view(s)}}
      {:error, _} -> :not_found
    end
  end

  defp view(s) do
    %{
      villain_image: villain_image(s),
      villain_name: villain_name(s),
      villain_set_name: s.villain_set && s.villain_set.name,
      overall_stats: combined_stats([s.villain_set | s.modular_sets]),
      modular_sets:
        s.modular_sets
        |> Enum.sort_by(&String.downcase(&1.name || &1.code))
        |> Enum.map(&encounter_set_view/1),
      description: Sanctum.Decks.Writeup.render(s.description_md),
      author: author(s),
      # :mine loads nil for a nil actor.
      mine: s.mine == true
    }
  end
end
