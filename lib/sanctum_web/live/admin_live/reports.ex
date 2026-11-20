defmodule SanctumWeb.AdminLive.Reports do
  @moduledoc """
  The homebrew moderation queue at `/admin/reports`: open `SetReport`s,
  oldest first, each with the two ways to action it — take the set down
  (`Homebrew.take_down_set/2`, an unpublish that keeps the set and also
  closes every open report on it) or dismiss the report. Below the queue,
  sets currently taken down can be restored (the creator then decides
  whether to republish). Gated by the `:admin_routes` live session.
  """
  use SanctumWeb, :live_view

  alias Sanctum.Homebrew

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Homebrew reports")
     |> load()}
  end

  defp load(socket) do
    actor = socket.assigns.current_user

    socket
    |> assign(:reports, Homebrew.list_open_set_reports!(actor: actor))
    |> assign(:taken_down, Homebrew.list_taken_down_sets!(actor: actor))
  end

  @impl true
  def handle_event("take_down", %{"set-id" => set_id}, socket) do
    actor = socket.assigns.current_user

    with {:ok, set} <- Homebrew.get_set(set_id, actor: actor),
         {:ok, _set} <- Homebrew.take_down_set(set, actor: actor) do
      {:noreply, socket |> put_flash(:info, "Set taken down.") |> load()}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not take that set down.")}
    end
  end

  def handle_event("dismiss", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    case Enum.find(socket.assigns.reports, &(&1.id == id)) do
      nil ->
        {:noreply, load(socket)}

      report ->
        case Homebrew.dismiss_set_report(report, actor: actor) do
          {:ok, _report} ->
            {:noreply, socket |> put_flash(:info, "Report dismissed.") |> load()}

          {:error, _error} ->
            {:noreply, put_flash(socket, :error, "Could not dismiss that report.")}
        end
    end
  end

  def handle_event("restore", %{"set-id" => set_id}, socket) do
    actor = socket.assigns.current_user

    case Enum.find(socket.assigns.taken_down, &(&1.id == set_id)) do
      nil ->
        {:noreply, load(socket)}

      set ->
        case Homebrew.restore_set(set, actor: actor) do
          {:ok, _set} ->
            {:noreply,
             socket
             |> put_flash(
               :info,
               "Takedown lifted. The set stays private until its creator republishes."
             )
             |> load()}

          {:error, _error} ->
            {:noreply, put_flash(socket, :error, "Could not restore that set.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:admin}>
      <.link
        navigate={~p"/admin"}
        class="mb-3 inline-flex items-center gap-1 font-ibm-mono text-xs uppercase tracking-[0.16em] text-base-content/50 hover:text-primary"
      >
        <.icon name="hero-arrow-left" class="size-3.5" /> Admin
      </.link>

      <.header>
        Homebrew reports
      </.header>

      <p
        id="open-report-count"
        class="-mt-3 mb-4 font-ibm-mono text-xs uppercase tracking-[0.16em] text-base-content/50"
      >
        {length(@reports)} open
      </p>

      <p :if={@reports == []} id="reports-empty" class="font-barlow-condensed text-base-content/60">
        No open reports.
      </p>

      <ul id="open-reports" class="flex flex-col gap-3">
        <li
          :for={report <- @reports}
          id={"report-#{report.id}"}
          class="flex flex-col gap-2 border-[3px] border-neutral bg-base-300 p-4"
        >
          <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
            <.set_link set={report.homebrew_set} />
            <span class="font-ibm-mono text-xs uppercase tracking-[0.16em] text-warning">
              {Sanctum.Homebrew.SetReportReason.description(report.reason)}
            </span>
            <span class="font-ibm-mono text-xs text-base-content/50">
              reported by @{report.reporter.username || "anonymous user"} · {Calendar.strftime(
                report.inserted_at,
                "%b %-d, %Y"
              )}
            </span>
          </div>
          <p
            :if={report.details}
            class="whitespace-pre-line font-barlow text-sm text-base-content/80"
          >
            {report.details}
          </p>
          <div class="flex flex-wrap gap-2">
            <.confirm_button
              id={"take-down-#{report.id}"}
              message={"Take down “#{report.homebrew_set.name}”? It becomes private and can't be shared again until restored. Nothing is deleted."}
              confirm_label="Take down"
              phx-click="take_down"
              phx-value-set-id={report.homebrew_set_id}
              class="cursor-pointer border-2 border-transparent bg-error px-3 py-1.5 font-barlow-condensed text-sm font-extrabold uppercase tracking-[0.08em] text-white shadow-comic-sm"
            >
              Take down set
            </.confirm_button>
            <.button
              id={"dismiss-#{report.id}"}
              variant="ghost"
              phx-click="dismiss"
              phx-value-id={report.id}
              class="px-3 py-1.5"
            >
              Dismiss
            </.button>
          </div>
        </li>
      </ul>

      <section class="mt-10">
        <h2 class="mb-3 font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/50">
          Taken down
        </h2>
        <p
          :if={@taken_down == []}
          id="taken-down-empty"
          class="font-barlow-condensed text-base-content/60"
        >
          No sets are taken down.
        </p>
        <ul id="taken-down-sets" class="flex flex-col gap-2">
          <li
            :for={set <- @taken_down}
            id={"taken-down-#{set.id}"}
            class="flex flex-wrap items-center justify-between gap-2 border-2 border-neutral bg-base-200 px-4 py-2"
          >
            <span class="font-barlow-condensed">
              <span class="font-bold">{set.name}</span>
              <span class="text-base-content/55">
                by @{set.creator.username || "unnamed creator"} · taken down {Calendar.strftime(
                  set.taken_down_at,
                  "%b %-d, %Y"
                )}
              </span>
            </span>
            <.button
              id={"restore-#{set.id}"}
              variant="ghost"
              phx-click="restore"
              phx-value-set-id={set.id}
              class="px-3 py-1.5"
            >
              Restore
            </.button>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  # A live set links to its public page; one already down has no public page.
  attr :set, :any, required: true

  defp set_link(assigns) do
    ~H"""
    <.link
      :if={(@set.visibility != :private and @set.slug) && @set.creator.username}
      navigate={~p"/custom/@#{to_string(@set.creator.username)}/#{@set.slug}"}
      class="font-barlow-condensed text-lg font-bold text-primary hover:underline"
    >
      {@set.name}
    </.link>
    <span
      :if={!((@set.visibility != :private and @set.slug) && @set.creator.username)}
      class="font-barlow-condensed text-lg font-bold"
    >
      {@set.name}
    </span>
    <span class="font-barlow-condensed text-sm text-base-content/55">
      by @{@set.creator.username || "unnamed creator"} · {@set.visibility}
    </span>
    """
  end
end
