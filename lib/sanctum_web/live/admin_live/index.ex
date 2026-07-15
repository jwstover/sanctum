defmodule SanctumWeb.AdminLive.Index do
  @moduledoc """
  Admin landing page: a quick system-health snapshot plus links to the
  admin-only surfaces. Gated by the `:admin_routes` live session, so a
  non-admin never reaches `mount/3`.
  """
  use SanctumWeb, :live_view

  import Ecto.Query, only: [from: 2]

  @job_states [:available, :executing, :scheduled, :retryable, :discarded, :cancelled, :completed]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:admin}>
      <.header>
        Admin
        <:subtitle>System health and management surfaces.</:subtitle>
      </.header>

      <section class="mt-6">
        <h2 class="mb-3 font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/50">
          Catalog
        </h2>
        <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
          <.stat_tile label="Cards" value={@stats.cards} />
          <.stat_tile label="Card Sides" value={@stats.card_sides} />
          <.stat_tile label="Decks" value={@stats.decks} />
          <.stat_tile label="Heroes" value={@stats.heroes} />
          <.stat_tile label="Villains" value={@stats.villains} />
          <.stat_tile label="Scenarios" value={@stats.scenarios} />
          <.stat_tile label="Users" value={@stats.users} />
          <.stat_tile label="Games" value={@stats.games} />
        </div>
      </section>

      <section class="mt-8">
        <h2 class="mb-3 font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/50">
          Background Jobs
        </h2>
        <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
          <.stat_tile label="Available" value={@jobs.available} />
          <.stat_tile label="Executing" value={@jobs.executing} />
          <.stat_tile label="Scheduled" value={@jobs.scheduled} />
          <.stat_tile label="Retryable" value={@jobs.retryable} accent={@jobs.retryable > 0} />
          <.stat_tile label="Discarded" value={@jobs.discarded} accent={@jobs.discarded > 0} />
          <.stat_tile label="Completed" value={@jobs.completed} />
        </div>
      </section>

      <section class="mt-8">
        <h2 class="mb-3 font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/50">
          Import Deck
        </h2>
        <div class="border-[3px] border-neutral bg-base-300 p-4 space-y-3">
          <form phx-submit="import_deck" class="flex flex-col gap-3 sm:flex-row sm:items-start">
            <div class="w-full">
              <.input
                name="deck_url"
                value={@deck_import.url}
                placeholder="https://marvelcdb.com/decklist/view/…"
                autocomplete="off"
              />
            </div>
            <.button variant="primary" disabled={@deck_import.status == :running}>
              <.icon name="hero-arrow-down-tray" />
              {if @deck_import.status == :running, do: "Importing…", else: "Import"}
            </.button>
          </form>

          <p class="font-ibm-mono text-xs text-base-content/40">
            Paste a MarvelCDB decklist or deck URL to sync that deck into Sanctum.
          </p>

          <p
            :if={@deck_import.status == :error}
            class="break-words font-ibm-mono text-xs text-error"
          >
            {@deck_import.error}
          </p>

          <div
            :if={@deck_import.status == :done}
            class="flex flex-wrap items-center gap-x-3 gap-y-1 font-ibm-mono text-xs"
          >
            <span class="text-success">Imported “{@deck_import.deck.title}”</span>
            <%!-- href, not navigate: /decks/:id is in a different live_session --%>
            <.link href={~p"/decks/#{@deck_import.deck.id}"} class="text-primary underline">
              Open deck view →
            </.link>
          </div>
        </div>
      </section>

      <section class="mt-8">
        <h2 class="mb-3 font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/50">
          Manage
        </h2>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <.admin_link navigate={~p"/admin/cards"} icon="hero-rectangle-stack" title="Manage Cards">
            Browse, edit, and delete the card catalog.
          </.admin_link>
          <.admin_link navigate={~p"/admin/cards/sync"} icon="hero-arrow-path" title="Sync Cards">
            Pull the latest catalog from MarvelCDB.
          </.admin_link>
          <.admin_link href={~p"/admin/oban"} icon="hero-queue-list" title="Job Monitor">
            Inspect and retry background jobs (Oban).
          </.admin_link>

          <.admin_link
            :if={@dev_routes?}
            href="/dev/dashboard"
            icon="hero-chart-bar"
            title="LiveDashboard"
          >
            Runtime metrics and processes (dev only).
          </.admin_link>
          <.admin_link :if={@dev_routes?} href="/admin/ash" icon="hero-circle-stack" title="AshAdmin">
            Raw resource management (dev only).
          </.admin_link>
          <.admin_link :if={@dev_routes?} href="/dev/mailbox" icon="hero-envelope" title="Mailbox">
            Preview sent emails (dev only).
          </.admin_link>
        </div>
      </section>

      <p class="mt-8 font-ibm-mono text-xs text-base-content/40">
        Sanctum v{Application.spec(:sanctum, :vsn)}
      </p>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :accent, :boolean, default: false

  defp stat_tile(assigns) do
    ~H"""
    <div class={[
      "border-[3px] border-neutral bg-base-300 px-4 py-3",
      @accent && "bg-error/15"
    ]}>
      <div class={[
        "font-bangers text-3xl leading-none",
        (@accent && "text-error") || "text-primary"
      ]}>
        {@value}
      </div>
      <div class="mt-1 font-ibm-mono text-[11px] uppercase tracking-[0.15em] text-base-content/55">
        {@label}
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :rest, :global, include: ~w(href navigate patch)
  slot :inner_block, required: true

  defp admin_link(assigns) do
    ~H"""
    <.link
      class="group flex items-start gap-3 border-[3px] border-neutral bg-base-300 px-4 py-3.5 transition-colors hover:border-primary"
      {@rest}
    >
      <.icon name={@icon} class="mt-0.5 size-6 text-primary" />
      <div>
        <div class="font-barlow-condensed text-lg font-bold uppercase tracking-[0.06em] text-base-content group-hover:text-white">
          {@title}
        </div>
        <div class="mt-0.5 text-sm text-base-content/55">
          {render_slot(@inner_block)}
        </div>
      </div>
    </.link>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin")
     |> assign(:dev_routes?, Application.get_env(:sanctum, :dev_routes, false))
     |> assign(:stats, load_stats())
     |> assign(:jobs, load_job_counts())
     |> assign(:deck_import, %{status: :idle, deck: nil, error: nil, url: ""})}
  end

  @impl true
  def handle_event("import_deck", %{"deck_url" => url}, socket) do
    case parse_deck_url(url) do
      {:ok, canonical_url} ->
        {:noreply,
         socket
         |> assign(:deck_import, %{status: :running, deck: nil, error: nil, url: String.trim(url)})
         |> start_async(:import_deck, fn -> import_deck(canonical_url) end)}

      :error ->
        {:noreply,
         assign(socket, :deck_import, %{
           status: :error,
           deck: nil,
           error:
             "Not a MarvelCDB deck URL — expected marvelcdb.com/decklist/view/… or marvelcdb.com/deck/view/…",
           url: url
         })}
    end
  end

  @impl true
  def handle_async(:import_deck, {:ok, result}, socket) do
    deck_import = socket.assigns.deck_import

    socket =
      case result do
        {:ok, deck} ->
          socket
          |> assign(:deck_import, %{deck_import | status: :done, deck: deck})
          |> assign(:stats, load_stats())

        {:error, reason} ->
          assign(socket, :deck_import, %{
            deck_import
            | status: :error,
              error: import_error(reason)
          })
      end

    {:noreply, socket}
  end

  def handle_async(:import_deck, {:exit, reason}, socket) do
    deck_import = %{
      socket.assigns.deck_import
      | status: :error,
        error: "Import crashed: #{inspect(reason)}"
    }

    {:noreply, assign(socket, :deck_import, deck_import)}
  end

  # Accept anything a user is likely to paste — http/https, www, trailing slug
  # or query string — plus a bare decklist id, and reduce it to the canonical
  # URL form `MarvelCdb.load_deck/1` matches on.
  defp parse_deck_url(input) do
    input = String.trim(input)

    case Regex.run(~r{marvelcdb\.com/(decklist|deck)/view/(\d+)}, input) do
      [_, type, id] -> {:ok, "https://marvelcdb.com/#{type}/view/#{id}"}
      nil -> if input =~ ~r/^\d+$/, do: {:ok, input}, else: :error
    end
  end

  # load_deck can raise (e.g. a hero card missing from the catalog), not just
  # return `{:error, _}` — surface any raise as a failed import.
  defp import_deck(url) do
    Sanctum.MarvelCdb.load_deck(url)
  rescue
    exception -> {:error, Exception.format(:error, exception, __STACKTRACE__)}
  end

  defp import_error(:not_found),
    do: "MarvelCDB returned 404 — deck not found (private decks can't be fetched)."

  defp import_error(reason) when is_binary(reason), do: reason
  defp import_error(reason), do: inspect(reason)

  # Aggregate counts for the health snapshot. `authorize?: false` is deliberate:
  # the route is already admin-gated and these are non-sensitive row counts, so
  # we skip per-resource read policies rather than thread an actor through each.
  defp load_stats do
    %{
      cards: count(Sanctum.Games.Card),
      card_sides: count(Sanctum.Games.CardSide),
      decks: count(Sanctum.Decks.Deck),
      heroes: count(Sanctum.Heroes.Hero),
      villains: count(Sanctum.Villains.Villain),
      scenarios: count(Sanctum.Games.Scenario),
      users: count(Sanctum.Accounts.User),
      games: count(Sanctum.Games.Game)
    }
  end

  defp count(resource) do
    Ash.count!(resource, authorize?: false)
  rescue
    _ -> 0
  end

  # Oban jobs aren't Ash resources; query the framework table directly for a
  # by-state tally, keyed by the raw state string. We then project onto the
  # fixed @job_states set (avoiding String.to_atom on DB values). Falls back to
  # zeros if the table isn't available.
  defp load_job_counts do
    counts =
      from(j in "oban_jobs", group_by: j.state, select: {j.state, count(j.id)})
      |> Sanctum.Repo.all()
      |> Map.new()

    Map.new(@job_states, fn state -> {state, Map.get(counts, Atom.to_string(state), 0)} end)
  rescue
    _ -> Map.new(@job_states, &{&1, 0})
  end
end
