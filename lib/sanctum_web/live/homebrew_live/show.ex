defmodule SanctumWeb.HomebrewLive.Show do
  @moduledoc """
  A homebrew project page: drag-drop image upload plus the project's cards as
  an art grid. Every uploaded image immediately becomes a playable custom card
  — name is prefilled from the filename, all other metadata is optional
  (enrichment ships later).
  """

  use SanctumWeb, :live_view

  alias Sanctum.Homebrew
  alias Sanctum.HomebrewImages

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Homebrew.get_project(id, actor: socket.assigns.current_user) do
      {:ok, project} ->
        {:ok,
         socket
         |> assign(:page_title, project.name)
         |> assign(:project, project)
         |> assign(:uploads_configured?, HomebrewImages.configured?())
         |> assign_cards()
         |> allow_upload(:card_images,
           accept: ~w(.png .jpg .jpeg .webp),
           max_entries: 30,
           max_file_size: 20_000_000
         )}

      {:error, _not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found.")
         |> push_navigate(to: ~p"/homebrew")}
    end
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_entry", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :card_images, ref)}
  end

  def handle_event("save_uploads", _params, socket) do
    %{project: project, current_user: user} = socket.assigns

    results =
      consume_uploaded_entries(socket, :card_images, fn %{path: path}, entry ->
        {:ok, store_entry(path, entry, project, user)}
      end)

    created = Enum.count(results, &match?({:ok, _card}, &1))
    failed = for {:error, filename, _reason} <- results, do: filename

    socket =
      socket
      |> assign_cards()
      |> flash_outcome(created, failed)

    {:noreply, socket}
  end

  def handle_event("delete_card", %{"id" => id}, socket) do
    case Homebrew.destroy_custom_card(id, socket.assigns.current_user) do
      :ok -> {:noreply, assign_cards(socket)}
      _error -> {:noreply, put_flash(socket, :error, "Could not delete the card.")}
    end
  end

  # consume_uploaded_entries callback body: read the temp file, store the
  # normalized image under its content-addressed key, and mint the custom
  # card. Always consumed; per-entry outcome inspected by the caller.
  #
  # `path` is a LiveView-owned temp-upload path, not user-controlled input, so
  # Sobelow's Traversal.FileModule finding here is a false positive (ignored
  # project-wide in .sobelow-conf).
  defp store_entry(path, entry, project, user) do
    with {:ok, body} <- File.read(path),
         {:ok, url} <- HomebrewImages.store(body, entry.client_type),
         {:ok, card} <-
           Homebrew.create_custom_card(
             %{
               homebrew_project_id: project.id,
               card_sides: [%{image_url: url, filename: entry.client_name}]
             },
             user
           ) do
      {:ok, card}
    else
      error -> {:error, entry.client_name, error}
    end
  end

  defp flash_outcome(socket, 0, []), do: socket

  defp flash_outcome(socket, created, []) do
    put_flash(socket, :info, "#{created} #{if created == 1, do: "card", else: "cards"} added.")
  end

  defp flash_outcome(socket, created, failed) do
    socket
    |> flash_outcome(created, [])
    |> put_flash(:error, "Could not add: #{Enum.join(failed, ", ")}")
  end

  defp assign_cards(socket) do
    cards =
      Homebrew.list_project_cards(socket.assigns.project.id, socket.assigns.current_user)

    assign(socket, :cards, cards)
  end

  defp upload_error_to_string(:too_large), do: "File is too large (max 20 MB)."
  defp upload_error_to_string(:not_accepted), do: "Unsupported file type (use PNG, JPG, or WebP)."
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 30 at a time)."
  defp upload_error_to_string(_other), do: "Invalid file."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:homebrew}>
      <.header>
        {@project.name}
      </.header>

      <.panel :if={!@uploads_configured?} class="mb-6 p-5">
        <p class="font-barlow-condensed text-base-content/70">
          Image storage is not configured — set the S3 environment variables
          (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_ENDPOINT_URL_S3, BUCKET_NAME)
          to enable uploads.
        </p>
      </.panel>

      <form
        :if={@uploads_configured?}
        id="upload-form"
        phx-change="validate"
        phx-submit="save_uploads"
        class="mb-6"
      >
        <div
          phx-drop-target={@uploads.card_images.ref}
          class="flex flex-col items-center gap-3 border-2 border-dashed border-neutral bg-base-200 p-8 text-center"
        >
          <p class="font-barlow-condensed text-base-content/70">
            Drop card images here (PNG, JPG, WebP) — each image becomes a card.
          </p>
          <.live_file_input
            upload={@uploads.card_images}
            class="file-input file-input-sm max-w-xs font-barlow-condensed"
          />

          <ul
            :if={@uploads.card_images.entries != []}
            class="w-full max-w-md text-left font-barlow-condensed text-[13px]"
          >
            <li
              :for={entry <- @uploads.card_images.entries}
              class="flex items-center justify-between gap-2 border-b border-neutral/40 py-1"
            >
              <span class="truncate">{entry.client_name}</span>
              <span class="flex shrink-0 items-center gap-2">
                <span class="text-base-content/50">{entry.progress}%</span>
                <button
                  type="button"
                  phx-click="cancel_entry"
                  phx-value-ref={entry.ref}
                  aria-label="cancel"
                  class="text-base-content/60 hover:text-base-content"
                >
                  &times;
                </button>
              </span>
              <span :for={err <- upload_errors(@uploads.card_images, entry)} class="text-error">
                {upload_error_to_string(err)}
              </span>
            </li>
          </ul>

          <p :for={err <- upload_errors(@uploads.card_images)} class="text-error">
            {upload_error_to_string(err)}
          </p>

          <.button
            :if={@uploads.card_images.entries != []}
            variant="primary"
            type="submit"
          >
            Add {length(@uploads.card_images.entries)} {if length(@uploads.card_images.entries) == 1,
              do: "card",
              else: "cards"}
          </.button>
        </div>
      </form>

      <div
        :if={@cards == []}
        class="border-2 border-dashed border-neutral p-10 text-center"
      >
        <p class="font-barlow-condensed text-base-content/60">
          No cards yet — drop images above to add some.
        </p>
      </div>

      <div class="grid grid-cols-[repeat(auto-fill,minmax(110px,1fr))] gap-2.5">
        <div :for={card <- @cards} class="group relative">
          <div class="aspect-[63/88] border-2 border-neutral shadow-comic-sm">
            <.mc_card
              name={card.primary_side && card.primary_side.name}
              image_url={card.primary_side && card.primary_side.image_url}
              size="md"
              show_cost={false}
            />
          </div>
          <button
            type="button"
            phx-click="delete_card"
            phx-value-id={card.id}
            data-confirm="Delete this card?"
            aria-label="delete card"
            class="absolute right-1 top-1 hidden border-2 border-neutral bg-base-100/90 px-1.5 font-bold text-error group-hover:block"
          >
            &times;
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
