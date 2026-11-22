defmodule SanctumWeb.HomebrewLive.Directory do
  @moduledoc """
  The public custom-content directory at `/custom`: a flat, filterable grid
  of *published* homebrew sets (`HomebrewSet :directory`) — the `/decks`
  shape, not `/browse`'s wave hierarchy, because homebrew has no release
  cadence to hang a hierarchy on.

  Facets (kind, creator, tag, recency) live in the URL, so filtered views
  are shareable and survive back/forward; they combine with AND. Sets with
  no kind (or a project-specific custom kind) are found under "Other".
  """

  use SanctumWeb, :live_view

  import SanctumWeb.HomebrewComponents

  alias Sanctum.Homebrew
  alias Sanctum.Homebrew.SetKind
  alias SanctumWeb.HomebrewLive.Support

  on_mount {SanctumWeb.LiveUserAuth, :live_user_optional}

  @page_size 48
  @facets ~w(kind creator tag recency)
  @recency_options [{"Past week", "week"}, {"Past month", "month"}, {"Past year", "year"}]
  @recency_values Enum.map(@recency_options, &elem(&1, 1))

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns[:current_user]
    facets = Homebrew.directory_facets!(actor: actor)

    {:ok,
     socket
     |> assign(:page_title, "Custom Content")
     |> assign(:kind_options, kind_options())
     |> assign(:creator_options, facets.creators)
     |> assign(:tag_options, facets.tags)
     |> assign(:recency_options, @recency_options)
     |> assign(:limit, @page_size)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters =
      @facets
      |> Map.new(&{&1, blank_to_nil(params[&1])})
      |> Map.update!("recency", &((&1 in @recency_values && &1) || nil))

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:limit, @page_size)
     |> load_sets()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, push_patch(socket, to: directory_path(Map.take(params, @facets)), replace: true)}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/custom")}
  end

  def handle_event("load_more", _params, socket) do
    {:noreply,
     socket
     |> update(:limit, &(&1 + @page_size))
     |> load_sets()}
  end

  defp load_sets(socket) do
    %{filters: filters, limit: limit} = socket.assigns

    input =
      for {facet, value} <- filters, value, into: %{}, do: {String.to_existing_atom(facet), value}

    page =
      Homebrew.list_directory_sets!(input,
        actor: socket.assigns[:current_user],
        page: [limit: limit, offset: 0, count: true]
      )

    socket
    |> assign(:sets, Enum.map(page.results, &set_view/1))
    |> assign(:count, page.count)
    |> assign(:more?, page.more?)
  end

  defp set_view(set) do
    username = set.creator && to_string(set.creator.username)

    %{
      id: set.id,
      name: set.name,
      creator: username,
      path: ~p"/custom/@#{username || ""}/#{set.slug}",
      banner: Support.banner_src(set.banner_url),
      kind: kind_label(set.set_kind),
      tags: set.tags || [],
      card_count: set.card_count || 0
    }
  end

  # Unclassified sets read as "Other" — the same bucket the kind facet files
  # them under.
  defp kind_label(nil), do: "Other"
  defp kind_label(%{label: label}), do: label

  # Official kinds in display order; the official "other" row is folded into
  # the single "Other" catch-all (no kind / other / custom kinds), last.
  defp kind_options do
    official =
      for %{key: key, label: label} <- SetKind.official(), key != "other", do: {label, key}

    official ++ [{"Other", "other"}]
  end

  defp directory_path(params) do
    query = for {k, v} <- params, k in @facets, v not in [nil, ""], into: %{}, do: {k, v}
    ~p"/custom?#{query}"
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value) when is_binary(value), do: value
  defp blank_to_nil(_value), do: nil

  defp active_filters?(filters), do: Enum.any?(filters, fn {_k, v} -> v end)

  defp card_count_label(1), do: "1 card"
  defp card_count_label(n), do: "#{n} cards"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash}>
      <.header>
        Custom Content
        <:actions>
          <.link
            id="alt-art-gallery-link"
            navigate={~p"/custom/alt-art"}
            class="font-ibm-mono text-xs uppercase tracking-[0.16em] text-base-content/60 hover:text-primary"
          >
            Alt art gallery →
          </.link>
        </:actions>
      </.header>

      <p class="-mt-3 mb-4 font-barlow-condensed text-base-content/70">
        Fan-made heroes, scenarios and cards published by the community.
      </p>

      <.fan_content_notice id="fan-content-notice" class="mb-6 max-w-3xl" />

      <form
        id="directory-filters"
        phx-change="filter"
        class="mb-4 grid grid-cols-2 gap-3 md:grid-cols-4"
      >
        <.input
          type="select"
          id="filter-kind"
          name="kind"
          label="Kind"
          prompt="All kinds"
          options={@kind_options}
          value={@filters["kind"]}
        />
        <.input
          type="select"
          id="filter-creator"
          name="creator"
          label="Creator"
          prompt="All creators"
          options={Enum.map(@creator_options, &{"@" <> &1, &1})}
          value={@filters["creator"]}
        />
        <.input
          type="select"
          id="filter-tag"
          name="tag"
          label="Tag"
          prompt="All tags"
          options={@tag_options}
          value={@filters["tag"]}
        />
        <.input
          type="select"
          id="filter-recency"
          name="recency"
          label="Published"
          prompt="Any time"
          options={@recency_options}
          value={@filters["recency"]}
        />
      </form>

      <div class="mb-4 flex items-center gap-3 font-anton text-base uppercase tracking-[0.05em]">
        <span id="directory-count">
          {@count} <span class="text-base-content/45">{if @count == 1, do: "set", else: "sets"}</span>
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

      <div
        :if={@sets != []}
        id="directory-sets"
        class="grid grid-cols-1 gap-4 sm:grid-cols-[repeat(auto-fill,minmax(300px,1fr))]"
      >
        <article
          :for={set <- @sets}
          id={"directory-set-#{set.id}"}
          class="mc-tile relative flex flex-col overflow-hidden border-2 border-neutral bg-base-200 shadow-comic"
        >
          <%!-- Stretched-link pattern: the whole tile navigates via this overlay anchor. --%>
          <.link navigate={set.path} aria-label={set.name} class="absolute inset-0 z-[1]">
            <span class="sr-only">{set.name}</span>
          </.link>
          <div class="relative h-36 border-b-2 border-neutral bg-base-300">
            <img
              :if={set.banner}
              src={set.banner}
              alt=""
              loading="lazy"
              class="h-full w-full object-cover"
            />
            <div :if={!set.banner} class="bg-card-hatch absolute inset-0"></div>
            <span class="set-kind absolute left-2 top-2 border-2 border-neutral bg-primary px-2 py-0.5 font-barlow-condensed text-xs font-bold uppercase tracking-[0.08em] text-primary-content">
              {set.kind}
            </span>
          </div>
          <div class="flex flex-1 flex-col gap-1.5 p-3.5">
            <h2 class="set-name break-words font-anton text-xl uppercase leading-[0.95]">
              {set.name}
            </h2>
            <div class="font-barlow-condensed text-sm">
              by <span class="set-creator font-bold text-primary">@{set.creator}</span>
            </div>
            <div :if={set.tags != []} class="flex flex-wrap gap-1.5">
              <span
                :for={tag <- set.tags}
                class="border-2 border-neutral bg-base-300 px-1.5 py-0.5 font-barlow-condensed text-[11px] font-bold uppercase tracking-[0.06em] text-base-content/70"
              >
                {tag}
              </span>
            </div>
            <div class="mt-auto flex items-center gap-2 pt-2">
              <span class="set-card-count font-ibm-mono text-xs text-base-content/50">
                {card_count_label(set.card_count)}
              </span>
              <.fan_content_notice compact class="ml-auto" />
            </div>
          </div>
        </article>
      </div>

      <div :if={@more?} class="mt-6 flex justify-center">
        <.button id="load-more" variant="ghost" phx-click="load_more">Load more</.button>
      </div>

      <.panel
        :if={@sets == []}
        id="directory-empty"
        class="mt-2 border-dashed !border-[#2a2a30] px-6 py-12 text-center !shadow-none"
      >
        <%= if active_filters?(@filters) do %>
          <div class="font-bangers text-3xl tracking-[0.02em] text-primary">No sets found</div>
          <div class="mt-1.5 font-barlow text-sm text-base-content/55">
            Try a different combination or clear your filters.
          </div>
          <.button variant="primary" phx-click="clear" class="mt-4">Clear filters</.button>
        <% else %>
          <div class="font-bangers text-3xl tracking-[0.02em] text-primary">
            Nothing published yet
          </div>
          <div class="mt-1.5 font-barlow text-sm text-base-content/55">
            Published custom sets will appear here.
          </div>
        <% end %>
      </.panel>
    </Layouts.app>
    """
  end
end
