defmodule SanctumWeb.HomebrewLive.AltArtGallery do
  @moduledoc """
  The public alt-art gallery at `/custom/alt-art`: custom alt art from
  *published* homebrew sets (`CardAlt :gallery`), browsed card by card rather
  than as sets.

  Images are grouped by depicted character (the target card's hero, else its
  card set, else the card itself — `CardAlt.depicted`); the read sorts by it,
  so grouping is just chunking consecutive rows and stays stable across
  "Load more". Facets (artist, creator, target card) live in the URL and
  combine with AND. Every tile links to the official card it replaces and to
  the set that published it.
  """

  use SanctumWeb, :live_view

  import SanctumWeb.HomebrewComponents

  alias Sanctum.Games

  on_mount {SanctumWeb.LiveUserAuth, :live_user_optional}

  @page_size 60
  @facets ~w(artist creator card)

  @impl true
  def mount(_params, _session, socket) do
    facets = Games.alt_art_gallery_facets!(actor: socket.assigns[:current_user])

    {:ok,
     socket
     |> assign(:page_title, "Alt Art Gallery")
     |> assign(:artist_options, facets.artists)
     |> assign(:creator_options, Enum.map(facets.creators, &{"@" <> &1, &1}))
     |> assign(:card_options, Enum.map(facets.cards, &{&1.name, &1.id}))
     |> assign(:limit, @page_size)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters =
      @facets
      |> Map.new(&{&1, blank_to_nil(params[&1])})
      |> Map.update!("card", &valid_uuid/1)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:limit, @page_size)
     |> load_alts()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, push_patch(socket, to: gallery_path(Map.take(params, @facets)), replace: true)}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/custom/alt-art")}
  end

  def handle_event("load_more", _params, socket) do
    {:noreply,
     socket
     |> update(:limit, &(&1 + @page_size))
     |> load_alts()}
  end

  defp load_alts(socket) do
    %{filters: filters, limit: limit} = socket.assigns

    input =
      for {facet, value} <- filters, value, into: %{}, do: {String.to_existing_atom(facet), value}

    page =
      Games.list_alt_art_gallery!(input,
        actor: socket.assigns[:current_user],
        page: [limit: limit, offset: 0, count: true]
      )

    socket
    |> assign(:groups, group(page.results))
    |> assign(:count, page.count)
    |> assign(:more?, page.more?)
  end

  # Rows arrive sorted by `depicted`, so consecutive chunks are the groups.
  defp group(alts) do
    alts
    |> Enum.chunk_by(& &1.depicted)
    |> Enum.with_index()
    |> Enum.map(fn {[first | _] = chunk, index} ->
      %{
        id: "group-#{index}",
        name: first.depicted || "Other",
        alts: Enum.map(chunk, &alt_view/1)
      }
    end)
  end

  defp alt_view(alt) do
    card = alt.card

    side =
      Enum.find(card.card_sides, &(&1.side_identifier == alt.side_identifier)) ||
        card.primary_side

    set = alt.homebrew_set
    username = alt.creator && alt.creator.username && to_string(alt.creator.username)

    %{
      id: alt.id,
      image_url: https_or_nil(alt.image_url),
      card_name: (side && side.name) || card.code,
      card_path: ~p"/cards/#{card.id}",
      artist: alt.artist,
      creator: username,
      set_name: set && set.name,
      set_path: set && username && set.slug && ~p"/custom/@#{username}/#{set.slug}"
    }
  end

  defp https_or_nil("https://" <> _rest = url), do: url
  defp https_or_nil(_url), do: nil

  defp gallery_path(params) do
    query = for {k, v} <- params, k in @facets, v not in [nil, ""], into: %{}, do: {k, v}
    ~p"/custom/alt-art?#{query}"
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value) when is_binary(value), do: value
  defp blank_to_nil(_value), do: nil

  # A hand-edited ?card= that isn't a uuid would fail the read's cast.
  defp valid_uuid(nil), do: nil

  defp valid_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp active_filters?(filters), do: Enum.any?(filters, fn {_k, v} -> v end)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash}>
      <.header>
        Alt Art Gallery
        <:actions>
          <.link
            navigate={~p"/custom"}
            class="font-ibm-mono text-xs uppercase tracking-[0.16em] text-base-content/60 hover:text-primary"
          >
            Browse sets →
          </.link>
        </:actions>
      </.header>

      <p class="-mt-3 mb-4 font-barlow-condensed text-base-content/70">
        Fan-made alternate art for official cards, from published custom sets.
      </p>

      <.fan_content_notice id="fan-content-notice" class="mb-6 max-w-3xl" />

      <form
        id="gallery-filters"
        phx-change="filter"
        class="mb-4 grid grid-cols-1 gap-3 sm:grid-cols-3"
      >
        <.input
          type="select"
          id="filter-artist"
          name="artist"
          label="Artist"
          prompt="All artists"
          options={@artist_options}
          value={@filters["artist"]}
        />
        <.input
          type="select"
          id="filter-creator"
          name="creator"
          label="Creator"
          prompt="All creators"
          options={@creator_options}
          value={@filters["creator"]}
        />
        <.input
          type="select"
          id="filter-card"
          name="card"
          label="Card"
          prompt="All cards"
          options={@card_options}
          value={@filters["card"]}
        />
      </form>

      <div class="mb-4 flex items-center gap-3 font-anton text-base uppercase tracking-[0.05em]">
        <span id="gallery-count">
          {@count}
          <span class="text-base-content/45">{if @count == 1, do: "image", else: "images"}</span>
        </span>
        <button
          :if={active_filters?(@filters)}
          id="clear-filters"
          type="button"
          phx-click="clear"
          class="font-ibm-mono text-xs uppercase tracking-[0.16em] text-base-content/50 hover:text-primary"
        >
          Clear filters
        </button>
      </div>

      <div :if={@groups != []} id="gallery-groups" class="flex flex-col gap-8">
        <section :for={group <- @groups} id={group.id} class="gallery-group">
          <h2 class="group-name mb-3 border-b-2 border-neutral pb-1 font-anton text-2xl uppercase leading-none">
            {group.name}
            <span class="font-ibm-mono text-xs text-base-content/45">{length(group.alts)}</span>
          </h2>
          <div class="grid grid-cols-2 gap-4 sm:grid-cols-[repeat(auto-fill,minmax(180px,1fr))]">
            <figure
              :for={alt <- group.alts}
              id={"gallery-alt-#{alt.id}"}
              class="flex flex-col gap-1.5"
            >
              <.link
                navigate={alt.card_path}
                class="alt-card-link block overflow-hidden rounded-[4.5%] border-2 border-neutral bg-base-300 shadow-comic"
                aria-label={"#{alt.card_name} (official card)"}
              >
                <img
                  :if={alt.image_url}
                  src={alt.image_url}
                  alt={"Alt art for #{alt.card_name}"}
                  loading="lazy"
                  class="aspect-[63/88] w-full object-cover"
                />
                <div :if={!alt.image_url} class="bg-card-hatch aspect-[63/88] w-full"></div>
              </.link>
              <figcaption class="flex flex-col gap-0.5 font-barlow-condensed text-sm leading-tight">
                <.link navigate={alt.card_path} class="alt-card-name font-bold hover:text-primary">
                  {alt.card_name}
                </.link>
                <span :if={alt.artist} class="alt-artist text-base-content/70">
                  art by {alt.artist}
                </span>
                <span class="text-base-content/55">
                  <.link
                    :if={alt.set_path}
                    navigate={alt.set_path}
                    class="alt-set-link hover:text-primary"
                  >
                    {alt.set_name}
                  </.link>
                  <span :if={alt.creator} class="alt-creator">· @{alt.creator}</span>
                </span>
              </figcaption>
            </figure>
          </div>
        </section>
      </div>

      <div :if={@more?} class="mt-6 flex justify-center">
        <.button id="load-more" variant="ghost" phx-click="load_more">Load more</.button>
      </div>

      <.panel
        :if={@groups == []}
        id="gallery-empty"
        class="mt-2 border-dashed !border-[#2a2a30] px-6 py-12 text-center !shadow-none"
      >
        <%= if active_filters?(@filters) do %>
          <div class="font-bangers text-3xl tracking-[0.02em] text-primary">No art found</div>
          <div class="mt-1.5 font-barlow text-sm text-base-content/55">
            Try a different combination or clear your filters.
          </div>
          <.button variant="primary" phx-click="clear" class="mt-4">Clear filters</.button>
        <% else %>
          <div class="font-bangers text-3xl tracking-[0.02em] text-primary">
            No alt art yet
          </div>
          <div class="mt-1.5 font-barlow text-sm text-base-content/55">
            Alt art from published custom sets will appear here.
          </div>
        <% end %>
      </.panel>
    </Layouts.app>
    """
  end
end
