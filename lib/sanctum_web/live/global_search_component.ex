defmodule SanctumWeb.GlobalSearchComponent do
  @moduledoc """
  The site-wide search overlay: a `query_input` wired to
  `Sanctum.Search.Global`, rendered once from `Layouts.app/1` as a
  command-palette dialog — centered modal on desktop, slide-up sheet on
  mobile. Trigger buttons (sidebar, mobile header) and Cmd/Ctrl+K open it via
  a `sanctum:open-search` window event handled by the GlobalSearch hook;
  open/close state never touches the server.

  A LiveComponent (not layout markup handled by the host LiveView) because
  the pool and deck browser already define their own `"search"`/`"suggest"`
  events — `phx-target={@myself}` keeps the global bar's events isolated no
  matter which LiveView is mounted. Result fetching runs in `start_async` so
  slow queries never block the socket; a `req_id` guard drops stale replies.
  """

  use SanctumWeb, :live_component

  import SanctumWeb.Components.QueryInput

  alias Sanctum.Search.Global

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       query: "",
       groups: [],
       diagnostics: [],
       loading?: false,
       req_id: 0
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="global-search-overlay"
      data-gs-overlay
      class="fixed inset-0 z-50 hidden"
      role="dialog"
      aria-modal="true"
      aria-label="Site search"
    >
      <div class="absolute inset-0 bg-black/60" data-gs-close aria-hidden="true"></div>
      <div class="gs-sheet absolute inset-x-0 bottom-0 max-h-[85vh] border-t-[3px] border-neutral bg-base-100 p-3 pb-[max(env(safe-area-inset-bottom),0.75rem)] sm:inset-x-auto sm:bottom-auto sm:left-1/2 sm:top-[12vh] sm:w-[min(92vw,620px)] sm:-translate-x-1/2 sm:border-2 sm:shadow-comic-lg">
        <form
          id="global-search-form"
          phx-change="search"
          phx-submit="submit"
          phx-target={@myself}
          autocomplete="off"
          class="w-full"
        >
          <.query_input
            id="global-search"
            hook="GlobalSearch"
            name="query"
            value={@query}
            registry={Sanctum.Search.GlobalFields}
            placeholder="Search cards, decks, heroes… (try in:cards cost<=2)"
            placeholder_short="Search…"
            help_path={~p"/search-help"}
            panel_class="mt-3 hidden border-t-2 border-line"
          >
            <:results>
              <%!-- Navigable rows carry server-rendered ids (for
                   aria-activedescendant): the hook must never assign ids to
                   LiveView-managed elements — the DOM patcher tracks nodes by
                   id, and client-mutated ids corrupt the next diff. --%>
              <div :if={@groups != []} data-gs-content>
                <div :for={group <- @groups}>
                  <div class="flex items-baseline justify-between border-b border-line bg-base-300/60 px-3 py-1">
                    <span class="font-barlow-condensed text-[12px] font-bold uppercase tracking-[0.14em] text-base-content/60">
                      {group.label}
                    </span>
                    <.link
                      :if={group.more_url}
                      navigate={group.more_url}
                      id={"gs-more-#{group.type}"}
                      data-gs-nav
                      class="gs-more font-barlow-condensed text-[12px] uppercase tracking-wide text-primary/80 hover:text-primary"
                    >
                      all {String.downcase(group.label)} results →
                    </.link>
                  </div>
                  <%= for {result, index} <- Enum.with_index(group.results) do %>
                    <.link
                      :if={result.href}
                      navigate={result.href}
                      id={"gs-res-#{group.type}-#{index}"}
                      data-gs-nav
                      class="qi-option"
                    >
                      <span class="qi-option-label qi-kind-result">{result.title}</span>
                      <span :if={result.subtitle} class="qi-option-detail">{result.subtitle}</span>
                    </.link>
                    <div :if={is_nil(result.href)} class="qi-option cursor-default">
                      <span class="qi-option-label qi-kind-result">{result.title}</span>
                      <span :if={result.subtitle} class="qi-option-detail">{result.subtitle}</span>
                    </div>
                  <% end %>
                </div>
              </div>
              <div
                :if={@groups == [] and @loading?}
                data-gs-content
                class="px-3 py-2.5 font-barlow text-[13px] text-base-content/50"
              >
                Searching…
              </div>
              <div
                :if={@groups == [] and not @loading? and String.trim(@query) != ""}
                data-gs-content
                class="px-3 py-2.5 font-barlow text-[13px] text-base-content/50"
              >
                <span :if={@diagnostics == []}>No matches for this search.</span>
                <span :if={@diagnostics != []} class="text-primary/90">
                  ⚠ {hd(@diagnostics).message}
                </span>
              </div>
            </:results>
          </.query_input>
        </form>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    if String.trim(query) == "" do
      {:noreply, assign(socket, query: query, groups: [], diagnostics: [], loading?: false)}
    else
      req_id = socket.assigns.req_id + 1
      actor = socket.assigns[:current_user]

      {:noreply,
       socket
       |> assign(query: query, req_id: req_id, loading?: true)
       |> start_async({:search, req_id}, fn -> Global.search(query, actor) end)}
    end
  end

  def handle_event("suggest", %{"value" => value, "cursor" => cursor}, socket) do
    {:reply, Global.suggest(value, cursor), socket}
  end

  def handle_event("suggest", _params, socket), do: {:reply, %{items: []}, socket}

  # Enter with nothing highlighted and no results rendered yet: fall back to
  # navigating to the first result of a fresh search.
  def handle_event("submit", _params, socket) do
    case first_href(socket.assigns.groups) do
      nil -> {:noreply, socket}
      href -> {:noreply, push_navigate(socket, to: href)}
    end
  end

  @impl true
  def handle_async({:search, req_id}, {:ok, result}, socket) do
    if req_id == socket.assigns.req_id do
      {:noreply,
       assign(socket, groups: result.groups, diagnostics: result.diagnostics, loading?: false)}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:search, req_id}, {:exit, _reason}, socket) do
    if req_id == socket.assigns.req_id do
      {:noreply, assign(socket, loading?: false)}
    else
      {:noreply, socket}
    end
  end

  defp first_href(groups) do
    Enum.find_value(groups, fn group ->
      Enum.find_value(group.results, & &1.href)
    end)
  end
end
