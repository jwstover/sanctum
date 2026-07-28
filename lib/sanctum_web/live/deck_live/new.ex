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
