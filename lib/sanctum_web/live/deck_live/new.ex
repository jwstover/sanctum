defmodule SanctumWeb.DeckLive.New do
  @moduledoc """
  Hero picker for building a native deck: a card-art grid of every buildable
  hero and a name filter. Selecting a hero creates the deck immediately with a
  default title and navigates straight into the builder — no name or aspect is
  chosen here. The title defaults to "<Hero> Deck" (renamed later on the
  builder's Details tab) and the aspect is inferred from the cards as they're
  added (see `Sanctum.Decks.Legality`).
  """

  use SanctumWeb, :live_view

  require Ash.Query

  alias Sanctum.Decks
  alias SanctumWeb.Components.DeckCards

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Deck")
     |> assign(:heroes, load_heroes())
     |> assign(:filter, "")}
  end

  @impl true
  def handle_event("filter", %{"q" => q}, socket) do
    {:noreply, assign(socket, :filter, q)}
  end

  def handle_event("select_hero", %{"id" => id}, socket) do
    %{heroes: heroes, current_user: user} = socket.assigns

    case Enum.find(heroes, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      hero ->
        # Blank title defaults to "<Hero> Deck"; aspects are inferred in the
        # builder from the cards.
        case Decks.build_deck(%{hero_id: hero.id}, actor: user) do
          {:ok, deck} ->
            {:noreply, push_navigate(socket, to: ~p"/decks/#{deck.id}/build")}

          {:error, _error} ->
            {:noreply, put_flash(socket, :error, "Could not create the deck")}
        end
    end
  end

  # A hero is buildable when its identity card has a hero side and its set has
  # an alter-ego side somewhere. We don't require the alter-ego on the same card
  # — split-identity heroes (SP//dr: SP//dr Suit + Peni Parker) spread the two
  # forms across two cards in one set. Matches ValidateHero.
  defp load_heroes do
    sets_with_alter_ego = sets_with_alter_ego()

    Sanctum.Heroes.Hero
    |> Ash.Query.load([:display_name, :hero_side, card: [:card_sides]])
    |> Ash.read!(authorize?: false)
    |> Enum.filter(&buildable?(&1, sets_with_alter_ego))
    |> Enum.map(&hero_view/1)
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  defp buildable?(%{card: %{card_sides: sides, set: set}}, sets_with_alter_ego)
       when is_list(sides) do
    Enum.any?(sides, &(&1.type == :hero)) and MapSet.member?(sets_with_alter_ego, set)
  end

  defp buildable?(_hero, _sets), do: false

  # One query for every set that contains an alter-ego side, so `buildable?/2`
  # stays a membership check instead of an N+1 lookup per hero.
  defp sets_with_alter_ego do
    Sanctum.Games.Card
    |> Ash.Query.filter(exists(card_sides, type == :alter_ego))
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.set)
    |> MapSet.new()
  end

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

      <div class="grid grid-cols-[repeat(auto-fill,minmax(110px,1fr))] gap-2.5 pb-6">
        <button
          :for={hero <- @heroes}
          :if={visible?(hero, @filter)}
          type="button"
          phx-click="select_hero"
          phx-value-id={hero.id}
          class="aspect-[63/88] border-2 border-neutral text-left shadow-comic-sm transition-transform hover:-translate-y-0.5 hover:outline hover:outline-[3px] hover:outline-primary"
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
    </Layouts.app>
    """
  end
end
