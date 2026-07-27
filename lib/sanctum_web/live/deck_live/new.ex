defmodule SanctumWeb.DeckLive.New do
  @moduledoc """
  Hero picker for building a native deck: a card-art grid of every buildable
  hero, a name filter, and a sticky (never modal) confirm strip with title +
  aspect choices. Creating navigates straight into the builder.
  """

  use SanctumWeb, :live_view

  alias Sanctum.Decks
  alias SanctumWeb.Components.DeckCards

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  @aspects [
    {"aggression", "Aggression", "bg-aspect-aggression"},
    {"justice", "Justice", "bg-aspect-justice"},
    {"leadership", "Leadership", "bg-aspect-leadership"},
    {"protection", "Protection", "bg-aspect-protection"},
    {"pool", "'Pool", "bg-aspect-pool"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Deck")
     |> assign(:heroes, load_heroes())
     |> assign(:filter, "")
     |> assign(:selected, nil)
     |> assign(:chosen_aspects, [])
     |> assign(:aspect_options, @aspects)
     |> assign(:creating?, false)}
  end

  @impl true
  def handle_event("filter", %{"q" => q}, socket) do
    {:noreply, assign(socket, :filter, q)}
  end

  def handle_event("select_hero", %{"id" => id}, socket) do
    selected = Enum.find(socket.assigns.heroes, &(&1.id == id))
    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("clear_hero", _params, socket) do
    {:noreply, assign(socket, :selected, nil)}
  end

  def handle_event("toggle_aspect", %{"key" => aspect}, socket) do
    chosen = socket.assigns.chosen_aspects

    chosen =
      if aspect in chosen do
        List.delete(chosen, aspect)
      else
        chosen ++ [aspect]
      end

    {:noreply, assign(socket, :chosen_aspects, chosen)}
  end

  def handle_event("create", params, socket) do
    %{selected: selected, chosen_aspects: aspects, current_user: user} = socket.assigns

    if is_nil(selected) do
      {:noreply, put_flash(socket, :error, "Pick a hero first")}
    else
      attrs = %{
        hero_id: selected.id,
        title: Map.get(params, "title", ""),
        aspects: aspects
      }

      case Decks.build_deck(attrs, actor: user) do
        {:ok, deck} ->
          {:noreply, push_navigate(socket, to: ~p"/decks/#{deck.id}/build")}

        {:error, _error} ->
          {:noreply, put_flash(socket, :error, "Could not create the deck")}
      end
    end
  end

  # Heroes whose identity card has no alter-ego side (e.g. SP//dr) fail
  # ValidateHero on :build, so they aren't offered.
  defp load_heroes do
    Sanctum.Heroes.Hero
    |> Ash.Query.load([:display_name, :hero_side, card: [:card_sides]])
    |> Ash.read!(authorize?: false)
    |> Enum.filter(&buildable?/1)
    |> Enum.map(&hero_view/1)
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  defp buildable?(%{card: %{card_sides: sides}}) when is_list(sides) do
    Enum.any?(sides, &(&1.type == :hero)) and Enum.any?(sides, &(&1.type == :alter_ego))
  end

  defp buildable?(_hero), do: false

  defp hero_view(hero) do
    {gradient_from, gradient_to} = DeckCards.hero_gradient(hero)

    %{
      id: hero.id,
      name: hero.display_name,
      image_url: DeckCards.identity_image(hero),
      gradient_from: gradient_from,
      gradient_to: gradient_to
    }
  end

  defp visible?(hero, filter) do
    filter = filter |> String.trim() |> String.downcase()
    filter == "" or String.contains?(String.downcase(hero.name), filter)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:decks}>
      <.header>
        New Deck
      </.header>

      <form id="hero-filter" phx-change="filter" class="mb-4" onsubmit="return false">
        <.input
          type="text"
          name="q"
          value={@filter}
          placeholder="Filter heroes…"
          autocomplete="off"
          phx-debounce="150"
        />
      </form>

      <div class="grid grid-cols-[repeat(auto-fill,minmax(110px,1fr))] gap-2.5 pb-36 sm:pb-6">
        <button
          :for={hero <- @heroes}
          :if={visible?(hero, @filter)}
          type="button"
          phx-click="select_hero"
          phx-value-id={hero.id}
          class={[
            "aspect-[63/88] border-2 border-neutral text-left shadow-comic-sm transition-transform",
            @selected && @selected.id == hero.id &&
              "outline outline-[3px] outline-primary -translate-y-0.5"
          ]}
        >
          <.mc_card
            name={hero.name}
            aspect={:hero}
            image_url={hero.image_url}
            gradient_from={hero.gradient_from}
            gradient_to={hero.gradient_to}
            size="md"
            show_cost={false}
          />
        </button>
      </div>

      <form
        :if={@selected}
        id="deck-confirm"
        phx-submit="create"
        class="fixed inset-x-0 bottom-0 z-20 border-t-2 border-neutral bg-base-100/95 px-4 py-3 backdrop-blur sm:sticky sm:bottom-4 sm:mx-0 sm:border-2 sm:bg-base-200 sm:px-5 sm:py-4 sm:shadow-comic"
      >
        <div class="mx-auto flex max-w-3xl flex-col gap-3">
          <div class="flex items-center justify-between gap-3">
            <span class="font-anton text-base uppercase tracking-[0.05em]">
              {@selected.name}
            </span>
            <button
              type="button"
              phx-click="clear_hero"
              class="font-barlow-condensed text-sm font-bold uppercase tracking-[0.08em] text-base-content/60 hover:text-base-content"
            >
              Change hero
            </button>
          </div>

          <input
            type="text"
            name="title"
            placeholder={"#{@selected.name} Deck"}
            autocomplete="off"
            class="min-h-[44px] w-full border-[2.5px] border-line bg-black px-3 py-2 font-barlow-condensed text-base font-bold text-base-content outline-none focus:border-primary sm:min-h-0"
          />

          <div class="flex flex-wrap items-center gap-1.5">
            <.filter_pill
              :for={{key, label, dot_class} <- @aspect_options}
              active={key in @chosen_aspects}
              dot_class={dot_class}
              type="button"
              phx-click="toggle_aspect"
              phx-value-key={key}
            >
              {label}
            </.filter_pill>
            <span class="ml-1 font-barlow-condensed text-xs uppercase tracking-[0.06em] text-base-content/45">
              none = basic deck
            </span>
          </div>

          <.button variant="primary" type="submit" class="w-full sm:w-auto sm:self-end">
            Start Deck
          </.button>
        </div>
      </form>
    </Layouts.app>
    """
  end
end
