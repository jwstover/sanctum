defmodule SanctumWeb.HomebrewLive.Show do
  @moduledoc """
  A homebrew project page: drag-drop image upload, the project's cards and
  alt art as dossier-tile grids, and front/back pairing of two single-sided
  cards. Every uploaded image immediately becomes a playable custom card;
  editing happens on the card's own page (`HomebrewLive.EditCard`).
  """

  use SanctumWeb, :live_view

  import SanctumWeb.Components.CardSideTile

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
         |> assign(:hero_colors, Sanctum.Heroes.hero_color_map())
         |> assign(:uploads_configured?, HomebrewImages.configured?())
         |> assign(:pair_mode?, false)
         |> assign(:pair_selection, [])
         |> assign_cards()
         |> assign_alts()
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

  # -- Alt art ----------------------------------------------------------------

  def handle_event("revert_alt", %{"id" => id}, socket) do
    case Homebrew.revert_alt_art(id, socket.assigns.current_user) do
      {:ok, _new_card} ->
        {:noreply,
         socket
         |> assign_cards()
         |> assign_alts()
         |> put_flash(:info, "Converted back to a card.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not revert the alt art.")}
    end
  end

  def handle_event("delete_alt", %{"id" => id}, socket) do
    case Homebrew.destroy_alt_art(id, socket.assigns.current_user) do
      :ok -> {:noreply, socket |> assign_alts() |> put_flash(:info, "Alt art deleted.")}
      _error -> {:noreply, put_flash(socket, :error, "Could not delete the alt art.")}
    end
  end

  # -- Pairing --------------------------------------------------------------

  def handle_event("toggle_pair_mode", _params, socket) do
    {:noreply,
     socket
     |> assign(:pair_mode?, !socket.assigns.pair_mode?)
     |> assign(:pair_selection, [])}
  end

  def handle_event("toggle_pair_select", %{"id" => id}, socket) do
    selection = socket.assigns.pair_selection
    card = Enum.find(socket.assigns.cards, &(&1.id == id))

    selection =
      cond do
        is_nil(card) or card.is_multi_sided -> selection
        id in selection -> List.delete(selection, id)
        length(selection) >= 2 -> selection
        true -> selection ++ [id]
      end

    {:noreply, assign(socket, :pair_selection, selection)}
  end

  def handle_event("swap_pair_order", _params, socket) do
    {:noreply, assign(socket, :pair_selection, Enum.reverse(socket.assigns.pair_selection))}
  end

  def handle_event("pair_cards", _params, socket) do
    case socket.assigns.pair_selection do
      [front_id, back_id] ->
        case Homebrew.pair_custom_cards(front_id, back_id, socket.assigns.current_user) do
          {:ok, _paired} ->
            {:noreply,
             socket
             |> assign(:pair_mode?, false)
             |> assign(:pair_selection, [])
             |> assign_cards()
             |> put_flash(:info, "Cards paired.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not pair the cards.")}
        end

      _incomplete ->
        {:noreply, socket}
    end
  end

  # -- Upload plumbing --------------------------------------------------------

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

    # The pool's dossier tile, fed the primary side. side_view/2 degrades on
    # missing metadata (nil type/ownership/stats render nothing); customs have
    # no hero palette, so the color map misses and yields the fallback gradient.
    tiles =
      Enum.map(cards, fn card ->
        {card, side_view(%{card.primary_side | card: card}, socket.assigns.hero_colors)}
      end)

    socket
    |> assign(:cards, cards)
    |> assign(:card_tiles, tiles)
  end

  defp assign_alts(socket) do
    alts = Homebrew.list_project_alts(socket.assigns.project.id, socket.assigns.current_user)

    # An alt IS the official card wearing different art: render the targeted
    # side's real tile with the alt's image swapped in.
    tiles = Enum.map(alts, &{&1, alt_tile_view(&1, socket.assigns.hero_colors)})

    socket
    |> assign(:project_alts, alts)
    |> assign(:alt_tiles, tiles)
  end

  defp alt_tile_view(alt, hero_colors) do
    card = alt.card

    side =
      Enum.find(card.card_sides, &(&1.side_identifier == alt.side_identifier)) ||
        card.primary_side

    %{side_view(%{side | card: card}, hero_colors) | image_url: alt.image_url}
  end

  defp pair_role(id, [id | _]), do: "FRONT"
  defp pair_role(id, [_, id]), do: "BACK"
  defp pair_role(_id, _selection), do: nil

  defp card_name(cards, id) do
    case Enum.find(cards, &(&1.id == id)) do
      %{primary_side: %{name: name}} -> name
      _ -> "?"
    end
  end

  defp single_sided_count(cards), do: Enum.count(cards, &(!&1.is_multi_sided))

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

      <%!-- Not a header subtitle (that slot was dropped): the meta line is page
           content, and the "unofficial fan content" labeling is required on all
           homebrew surfaces (IP posture). --%>
      <p class="-mt-4 mb-5 font-barlow-condensed text-sm text-base-content/55">
        {length(@cards)} {if length(@cards) == 1, do: "card", else: "cards"}<span :if={
          @project_alts != []
        }> &middot; {length(@project_alts)} {if length(@project_alts) == 1,
          do: "alt",
          else: "alts"}</span>
        &middot; {@project.visibility} &middot; unofficial fan content
      </p>

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
            class="w-full max-w-md text-left font-barlow-condensed text-sm"
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

          <.button :if={@uploads.card_images.entries != []} variant="primary" type="submit">
            Add {length(@uploads.card_images.entries)} {if length(@uploads.card_images.entries) == 1,
              do: "card",
              else: "cards"}
          </.button>
        </div>
      </form>

      <div :if={single_sided_count(@cards) >= 2} class="mb-3 flex items-center gap-3">
        <.button phx-click="toggle_pair_mode">
          {(@pair_mode? && "Cancel pairing") || "Pair fronts & backs"}
        </.button>
        <span :if={@pair_mode?} class="font-barlow-condensed text-sm text-base-content/60">
          Tap two cards to pair them as one two-sided card.
        </span>
      </div>

      <div :if={@cards == []} class="border-2 border-dashed border-neutral p-10 text-center">
        <p class="font-barlow-condensed text-base-content/60">
          No cards yet — drop images above to add some.
        </p>
      </div>

      <div class="grid grid-cols-1 items-start gap-[18px] pb-28 sm:grid-cols-[repeat(auto-fill,minmax(452px,1fr))]">
        <div :for={{card, side} <- @card_tiles} class="relative">
          <div class={[
            pair_role(card.id, @pair_selection) &&
              "outline outline-[3px] outline-primary -translate-y-0.5",
            @pair_mode? && card.is_multi_sided && "opacity-40"
          ]}>
            <.card_side_tile side={side} size="md">
              <:actions>
                <.button
                  :if={!@pair_mode?}
                  variant="ghost"
                  navigate={~p"/homebrew/#{@project.id}/cards/#{card.id}"}
                  class="px-3 py-1.5"
                >
                  Edit
                </.button>
                <.button
                  :if={!@pair_mode?}
                  variant="ghost"
                  phx-click="delete_card"
                  phx-value-id={card.id}
                  data-confirm="Delete this card?"
                  class="px-3 py-1.5 text-error hover:text-error"
                >
                  Delete
                </.button>
              </:actions>
            </.card_side_tile>
          </div>

          <button
            :if={@pair_mode? && !card.is_multi_sided}
            type="button"
            phx-click="toggle_pair_select"
            phx-value-id={card.id}
            aria-label={"Select #{side.name} for pairing"}
            class="absolute inset-0 z-[3] cursor-pointer"
          ></button>

          <span
            :if={role = pair_role(card.id, @pair_selection)}
            class="absolute left-1 top-1 z-[4] border-2 border-neutral bg-primary px-1.5 font-barlow-condensed text-xs font-bold text-primary-content"
          >
            {role}
          </span>
          <span
            :if={@pair_mode? && card.is_multi_sided}
            class="absolute left-1 top-1 z-[4] border-2 border-neutral bg-base-300 px-1.5 font-barlow-condensed text-xs font-bold text-base-content/70"
          >
            2-SIDED
          </span>
        </div>
      </div>

      <div :if={@project_alts != []} class="mt-8">
        <h2 class="mb-3 font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/50">
          Alt Art ({length(@project_alts)})
        </h2>
        <div class="grid grid-cols-1 items-start gap-[18px] sm:grid-cols-[repeat(auto-fill,minmax(452px,1fr))]">
          <.card_side_tile
            :for={{alt, side} <- @alt_tiles}
            side={side}
            size="md"
            navigate={~p"/cards/#{alt.card_id}"}
          >
            <:actions>
              <span class="font-ibm-mono text-xs uppercase tracking-[0.16em] text-base-content/50">
                fan art{alt.artist && " · by #{alt.artist}"}
              </span>
              <.button
                variant="ghost"
                phx-click="revert_alt"
                phx-value-id={alt.id}
                data-confirm="Convert back to a standalone card in this project?"
                class="ml-auto px-3 py-1.5"
              >
                Revert
              </.button>
              <.button
                variant="ghost"
                phx-click="delete_alt"
                phx-value-id={alt.id}
                data-confirm="Delete this alt art permanently?"
                class="px-3 py-1.5 text-error hover:text-error"
              >
                Delete
              </.button>
            </:actions>
          </.card_side_tile>
        </div>
      </div>

      <.pair_strip
        :if={@pair_mode? && length(@pair_selection) == 2}
        pair_selection={@pair_selection}
        cards={@cards}
      />
    </Layouts.app>
    """
  end

  # Fixed bottom action strip once two cards are selected for pairing —
  # deck_live/new.ex's confirm-strip recipe (never a modal).
  defp pair_strip(assigns) do
    ~H"""
    <div class="fixed inset-x-0 bottom-0 z-20 border-t-2 border-neutral bg-base-100/95 px-4 py-3 backdrop-blur sm:sticky sm:bottom-4 sm:border-2 sm:bg-base-200 sm:px-5 sm:py-4 sm:shadow-comic">
      <div class="mx-auto flex max-w-3xl flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <span class="font-barlow-condensed text-sm font-bold uppercase tracking-[0.05em]">
          Front: {card_name(@cards, Enum.at(@pair_selection, 0))}
          <span class="text-base-content/50">→</span>
          Back: {card_name(@cards, Enum.at(@pair_selection, 1))}
        </span>
        <div class="flex items-center gap-2">
          <.button type="button" phx-click="swap_pair_order">Swap</.button>
          <.button variant="primary" type="button" phx-click="pair_cards">
            Pair as one card
          </.button>
        </div>
      </div>
    </div>
    """
  end
end
