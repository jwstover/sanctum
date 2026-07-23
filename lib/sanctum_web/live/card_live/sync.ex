defmodule SanctumWeb.CardLive.Sync do
  use SanctumWeb, :live_view

  alias Sanctum.CardSync.Server

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash}>
      <.header>
        Card Sync
        <:actions>
          <.back_button fallback={~p"/admin/cards"} />
        </:actions>
      </.header>

      <div class="space-y-6">
        <div class="rounded-lg border border-base-300 bg-base-200 p-4 space-y-4">
          <div class="flex items-center gap-3">
            <span class={[
              "inline-flex items-center rounded-full px-3 py-1 text-sm font-medium",
              status_class(@sync.status)
            ]}>
              {status_label(@sync.status)}
            </span>
            <span :if={@sync.started_at} class="text-sm text-base-content/60">
              started {Calendar.strftime(@sync.started_at, "%Y-%m-%d %H:%M:%S UTC")}
            </span>
            <span :if={@sync.finished_at} class="text-sm text-base-content/60">
              &middot; finished {Calendar.strftime(@sync.finished_at, "%Y-%m-%d %H:%M:%S UTC")}
            </span>
          </div>

          <div :if={@sync.status == :running} class="space-y-2">
            <div class="flex items-baseline justify-between text-sm">
              <span class="font-medium">{phase_label(@sync.phase)}</span>
              <span :if={@sync.total} class="tabular-nums text-base-content/70">
                {@sync.index} / {@sync.total}
              </span>
            </div>

            <div class="h-3 w-full overflow-hidden rounded-full bg-base-300">
              <div
                class="h-full rounded-full bg-primary transition-[width] duration-150"
                style={"width: #{percent(@sync)}%"}
              >
              </div>
            </div>

            <div :if={@sync.current} class="truncate text-sm text-base-content/70">
              {@sync.current}
            </div>
          </div>

          <div class="grid grid-cols-2 gap-3 sm:grid-cols-5 text-sm">
            <.stat label="Cards synced" value={@sync.data.synced} />
            <.stat label="Cards failed" value={@sync.data.failed} error?={@sync.data.failed > 0} />
            <.stat label="Images uploaded" value={@sync.images.uploaded} />
            <.stat label="Images skipped" value={@sync.images.skipped} />
            <.stat
              label="Images failed"
              value={@sync.images.failed}
              error?={@sync.images.failed > 0}
            />
          </div>
        </div>

        <form phx-submit="start" class="rounded-lg border border-base-300 bg-base-200 p-4 space-y-3">
          <label class="flex cursor-pointer items-center gap-2 text-sm">
            <input type="checkbox" name="skip_images" value="true" class="checkbox checkbox-sm" />
            Skip images (card data only)
          </label>
          <label class="flex cursor-pointer items-center gap-2 text-sm">
            <input type="checkbox" name="force" value="true" class="checkbox checkbox-sm" />
            Force re-upload of images already in the bucket
          </label>

          <.button variant="primary" disabled={@sync.status == :running}>
            <.icon name="hero-arrow-path" />
            {if @sync.status == :running, do: "Sync running…", else: "Start sync"}
          </.button>
        </form>

        <div :if={@sync.failures != []} class="rounded-lg border border-error/40 bg-base-200 p-4">
          <h3 class="mb-2 text-sm font-semibold text-error">
            Failures ({length(@sync.failures)} most recent)
          </h3>
          <ul class="space-y-1 text-xs font-mono text-base-content/80">
            <li :for={failure <- @sync.failures} class="truncate">{failure}</li>
          </ul>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :error?, :boolean, default: false

  defp stat(assigns) do
    ~H"""
    <div class="rounded-md bg-base-100 p-3">
      <div class="text-xs text-base-content/60">{@label}</div>
      <div class={["text-lg font-semibold tabular-nums", @error? && "text-error"]}>{@value}</div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Server.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Card Sync")
     |> assign(:sync, Server.status())}
  end

  @impl true
  def handle_event("start", params, socket) do
    opts = [
      images?: params["skip_images"] != "true",
      force?: params["force"] == "true"
    ]

    case Server.start_sync(opts) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Card sync started")}

      {:error, :already_running} ->
        {:noreply, put_flash(socket, :error, "A sync is already running")}

      {:error, {:missing_env, vars}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Missing bucket credentials (#{Enum.join(vars, ", ")}) — set them or check \"Skip images\""
         )}
    end
  end

  @impl true
  def handle_info({:card_sync, sync}, socket) do
    {:noreply, assign(socket, :sync, sync)}
  end

  defp percent(%{total: total, index: index}) when is_integer(total) and total > 0,
    do: Float.round(index / total * 100, 1)

  defp percent(_sync), do: 0

  defp status_label(:idle), do: "Idle"
  defp status_label(:running), do: "Running"
  defp status_label(:done), do: "Completed"
  defp status_label(:error), do: "Failed"

  defp status_class(:idle), do: "bg-base-300 text-base-content/70"
  defp status_class(:running), do: "bg-info/20 text-info"
  defp status_class(:done), do: "bg-success/20 text-success"
  defp status_class(:error), do: "bg-error/20 text-error"

  defp phase_label(:fetching), do: "Fetching card list from MarvelCDB…"
  defp phase_label(:data), do: "Syncing card data"
  defp phase_label(:images), do: "Mirroring images to the bucket"
  defp phase_label(_phase), do: ""
end
