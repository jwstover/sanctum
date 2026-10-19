defmodule SanctumWeb.GameLogLive.New do
  @moduledoc false

  use SanctumWeb, :live_view

  alias Sanctum.GameLog
  alias Sanctum.Games
  alias Sanctum.Heroes

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  @scenario_loads [villains: [:primary_side], main_schemes: [:primary_side], modular_sets: []]

  def mount(_params, _session, socket) do
    scenarios = Games.list_scenarios!() |> Enum.sort_by(& &1.name)

    hero_options =
      [load: [:display_name]]
      |> Heroes.list_heroes!()
      |> Enum.sort_by(& &1.display_name)
      |> Enum.map(&{&1.display_name, &1.id})

    aspect_options =
      Games.list_aspects!()
      |> Enum.sort_by(& &1.sort_order)
      |> Enum.map(&{&1.label, &1.key})

    {:ok,
     socket
     |> assign(:page_title, "Log a Game")
     |> assign(:scenario_options, Enum.map(scenarios, &{&1.name, &1.id}))
     |> assign(:hero_options, hero_options)
     |> assign(:aspect_options, aspect_options)
     |> assign(:scenario, nil)
     |> assign(:scenario_id, nil)
     |> assign(:main_scheme_id, nil)
     |> assign(:modular_set_codes, [])
     |> assign(:played_at, Date.utc_today())
     |> assign(:next_key, 1)
     |> assign(:players, [%{key: 0, hero_id: nil, aspect: nil}])}
  end

  # The whole form (scenario, date, main scheme, sets, players) posts here on
  # every change; state lives in assigns and is submitted from them.
  def handle_event("change", params, socket) do
    {:noreply,
     socket
     |> apply_scenario(params["scenario_id"])
     |> apply_scalars(params)
     |> apply_players(params["players"] || %{})}
  end

  def handle_event("add-player", _params, socket) do
    key = socket.assigns.next_key

    {:noreply,
     socket
     |> assign(:next_key, key + 1)
     |> update(:players, &(&1 ++ [%{key: key, hero_id: nil, aspect: nil}]))}
  end

  def handle_event("remove-player", %{"key" => key}, socket) do
    key = String.to_integer(key)
    {:noreply, update(socket, :players, &Enum.reject(&1, fn p -> p.key == key end))}
  end

  def handle_event("create", _params, socket) do
    a = socket.assigns

    params = %{
      scenario_id: a.scenario_id,
      played_at: a.played_at,
      modular_sets: a.modular_set_codes,
      main_scheme_id: a.main_scheme_id,
      logged_game_players: Enum.map(a.players, &%{hero_id: &1.hero_id, aspect: &1.aspect})
    }

    case GameLog.create_logged_game(params, actor: a.current_user) do
      {:ok, game} ->
        {:noreply, push_navigate(socket, to: ~p"/game-log/#{game.id}")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Exception.message(error))}
    end
  end

  defp apply_scenario(socket, id) when id in [nil, ""] do
    if socket.assigns.scenario_id && id == "" do
      socket
      |> assign(:scenario, nil)
      |> assign(:scenario_id, nil)
      |> assign(:main_scheme_id, nil)
      |> assign(:modular_set_codes, [])
    else
      socket
    end
  end

  defp apply_scenario(%{assigns: %{scenario_id: id}} = socket, id), do: socket

  defp apply_scenario(socket, id) do
    scenario = Games.get_scenario!(id, load: @scenario_loads)

    main_scheme_id =
      case scenario.main_schemes do
        [only] -> only.id
        _ -> nil
      end

    socket
    |> assign(:scenario, scenario)
    |> assign(:scenario_id, id)
    |> assign(:main_scheme_id, main_scheme_id)
    |> assign(:modular_set_codes, Enum.map(scenario.modular_sets, & &1.code))
  end

  defp apply_scalars(socket, params) do
    socket =
      case Date.from_iso8601(params["played_at"] || "") do
        {:ok, date} -> assign(socket, :played_at, date)
        _ -> socket
      end

    socket =
      if params["main_scheme_id"] && multiple_schemes?(socket.assigns.scenario) do
        assign(socket, :main_scheme_id, blank_to_nil(params["main_scheme_id"]))
      else
        socket
      end

    case params["modular_sets"] do
      codes when is_list(codes) ->
        assign(socket, :modular_set_codes, Enum.reject(codes, &(&1 == "")))

      _ ->
        socket
    end
  end

  defp apply_players(socket, submitted) do
    players =
      Enum.map(socket.assigns.players, fn player ->
        case submitted[to_string(player.key)] do
          %{} = p ->
            %{
              player
              | hero_id: blank_to_nil(p["hero_id"]),
                aspect: blank_to_nil(p["aspect"])
            }

          _ ->
            player
        end
      end)

    assign(socket, :players, players)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp multiple_schemes?(%{main_schemes: [_, _ | _]}), do: true
  defp multiple_schemes?(_), do: false

  defp ready?(a) do
    a.scenario_id != nil and a.players != [] and Enum.all?(a.players, & &1.hero_id) and
      (not multiple_schemes?(a.scenario) or a.main_scheme_id != nil)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:game_log}>
      <.header>Log a Game</.header>

      <form id="game-log-form" phx-change="change" phx-submit="create" class="max-w-2xl space-y-6">
        <div class="grid gap-4 sm:grid-cols-2">
          <.input
            type="select"
            id="scenario_id"
            name="scenario_id"
            label="Scenario"
            prompt="Choose a scenario…"
            options={@scenario_options}
            value={@scenario_id}
          />
          <.input type="date" id="played_at" name="played_at" label="Played on" value={@played_at} />
        </div>

        <div :if={@scenario}>
          <p class="font-barlow">
            Villain:
            <span class="font-bold">
              {@scenario.villains |> List.first() |> then(&(&1 && &1.primary_side.name))}
            </span>
          </p>
        </div>

        <.input
          :if={multiple_schemes?(@scenario)}
          type="select"
          id="main_scheme_id"
          name="main_scheme_id"
          label="Main scheme"
          prompt="Which main scheme was used?"
          options={Enum.map(@scenario.main_schemes, &{&1.primary_side.name, &1.id})}
          value={@main_scheme_id}
        />

        <fieldset :if={@scenario && @scenario.modular_sets != []}>
          <legend class="mb-2 font-barlow-condensed text-lg uppercase tracking-[0.08em]">
            Modular sets
          </legend>
          <input type="hidden" name="modular_sets[]" value="" />
          <label
            :for={set <- @scenario.modular_sets}
            class="flex items-center gap-2 py-1 font-barlow"
          >
            <input
              type="checkbox"
              name="modular_sets[]"
              value={set.code}
              checked={set.code in @modular_set_codes}
              class="checkbox checkbox-sm"
            />
            {set.name || set.code}
          </label>
        </fieldset>

        <fieldset class="space-y-3">
          <legend class="mb-2 font-barlow-condensed text-lg uppercase tracking-[0.08em]">
            Players
          </legend>
          <div :for={player <- @players} class="flex items-end gap-2">
            <div class="flex-1">
              <.input
                type="select"
                id={"hero-#{player.key}"}
                name={"players[#{player.key}][hero_id]"}
                label="Hero"
                prompt="Choose a hero…"
                options={@hero_options}
                value={player.hero_id}
              />
            </div>
            <div class="flex-1">
              <.input
                type="select"
                id={"aspect-#{player.key}"}
                name={"players[#{player.key}][aspect]"}
                label="Aspect"
                prompt="No aspect"
                options={@aspect_options}
                value={player.aspect}
              />
            </div>
            <.button
              :if={length(@players) > 1}
              type="button"
              variant="icon"
              phx-click="remove-player"
              phx-value-key={player.key}
              aria-label="Remove player"
            >
              <.icon name="hero-x-mark" class="size-4" />
            </.button>
          </div>
          <.button type="button" variant="ghost" phx-click="add-player">
            <.icon name="hero-plus" /> Add player
          </.button>
        </fieldset>

        <div class="flex gap-2">
          <.button variant="primary" type="submit" disabled={!ready?(assigns)}>
            Save game
          </.button>
          <.button type="button" variant="ghost" navigate={~p"/game-log"}>Cancel</.button>
        </div>
      </form>
    </Layouts.app>
    """
  end
end
