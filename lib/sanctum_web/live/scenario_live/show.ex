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

        <.header>
          {@scenario.name}
          <:actions>
            <.button
              :if={@view.mine}
              id="scenario-build"
              variant="primary"
              navigate={~p"/scenarios/#{@scenario.id}/build"}
            >
              <.icon name="hero-pencil-square" /> Edit
            </.button>
            <.back_button fallback={~p"/scenarios"} />
          </:actions>
        </.header>

        <div class="space-y-5">
          <!-- cover -->
          <.panel class="flex flex-col gap-5 p-4 sm:flex-row sm:items-start">
            <div
              class="h-[300px] w-[214px] flex-none self-center border-2 border-neutral shadow-comic sm:self-start"
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
              <div class="font-ibm-mono text-xs uppercase tracking-[0.25em] text-primary">
                Scenario · {@view.villain_set_name}
              </div>
              <h1 class="mt-1.5 font-anton text-4xl uppercase leading-[0.9] [text-wrap:balance] sm:text-5xl sm:leading-[0.88]">
                {@scenario.name}
              </h1>

              <span
                :if={@view.author && @view.author.official?}
                class="mt-3 inline-flex w-fit"
              >
                <.official_badge />
              </span>

              <div class="mt-4 flex flex-wrap items-end gap-x-6 gap-y-3">
                <div>
                  <div class="font-anton text-3xl leading-none">{length(@view.modular_sets)}</div>
                  <div class="mt-1 font-barlow-condensed text-xs font-bold uppercase tracking-[0.1em] text-base-content/50">
                    {(length(@view.modular_sets) == 1 && "Modular Set") || "Modular Sets"}
                  </div>
                </div>
                <div :if={@view.total_cards > 0}>
                  <div class="font-anton text-3xl leading-none">{@view.total_cards}</div>
                  <div class="mt-1 font-barlow-condensed text-xs font-bold uppercase tracking-[0.1em] text-base-content/50">
                    Encounter Cards
                  </div>
                </div>
                <div :if={@view.author && !@view.author.official?} class="flex items-center gap-2">
                  <.avatar name={@view.author.name} url={@view.author.avatar} size="md" />
                  <span class="font-barlow-condensed text-sm font-bold text-primary">
                    {@view.author.name}
                  </span>
                </div>
                <span class="font-barlow text-sm text-base-content/50">
                  Updated {Calendar.strftime(@scenario.updated_at, "%b %-d, %Y")}
                </span>
              </div>
            </div>
          </.panel>

          <div class="grid items-start gap-5 lg:grid-cols-[1.4fr_1fr]">
            <.panel id="scenario-description" class="min-w-0 p-5">
              <div class="font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/50">
                Description
              </div>
              <div :if={@view.description} class="mt-3 space-y-4">
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
              <div
                :if={!@view.description}
                class="mt-3 font-barlow text-sm italic text-base-content/45"
              >
                No description for this scenario.
              </div>
            </.panel>

            <div class="min-w-0 space-y-5">
              <.panel id="scenario-modular-sets" class="min-w-0 p-4">
                <div class="mb-3 flex items-center gap-2 border-b-2 border-neutral pb-2">
                  <div class="font-anton text-lg uppercase tracking-[0.05em]">In This Scenario</div>
                  <div class="ml-auto font-ibm-mono text-xs text-base-content/45">
                    {length(@view.modular_sets)} {(length(@view.modular_sets) == 1 && "set") ||
                      "sets"}
                  </div>
                </div>
                <div
                  :if={@view.modular_sets == []}
                  class="font-barlow text-sm italic text-base-content/45"
                >
                  No modular sets.
                </div>
                <div class="divide-y divide-neutral/50">
                  <div
                    :for={ms <- @view.modular_sets}
                    id={"modular-set-#{ms.code}"}
                    class="flex items-center gap-4 py-3 first:pt-0 last:pb-0"
                  >
                    <div class="flex-none">
                      <.card_fan cards={ms.fan} />
                    </div>
                    <div class="min-w-0 flex-1">
                      <div class="font-barlow-condensed text-[17px] font-bold uppercase tracking-[0.05em]">
                        {ms.name}
                      </div>
                      <div class="mt-1 text-xs text-base-content/50">Modular set</div>
                    </div>
                  </div>
                </div>
              </.panel>

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
          </div>
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
    overall_stats = combined_stats([s.villain_set | s.modular_sets])

    %{
      villain_image: villain_image(s),
      villain_name: villain_name(s),
      villain_set_name: s.villain_set && s.villain_set.name,
      overall_stats: overall_stats,
      total_cards: overall_stats.type_counts |> Map.values() |> Enum.sum(),
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
