defmodule SanctumWeb.HomebrewLive.Show do
  @moduledoc """
  A homebrew project page — the single content-and-upload surface. One Upload
  button opens a chooser whose options *are* the file pickers (a label wrapping
  a hidden `live_file_input`), so choosing a type opens the OS picker in the
  same click — no extra step. Uploads are `auto_upload`, consumed as they
  finish in `handle_progress/3`:

    * **Cards** — each image becomes a custom `Card`, appearing in the grid.
    * **Alt art** — each image lands in a "to assign" strip; assigning it to an
      official card + side mints a `CardAlt` (`Homebrew.create_alt_art/2`).

  Also does front/back pairing of two single-sided cards; editing a card is on
  its own page (`HomebrewLive.EditCard`).
  """

  use SanctumWeb, :live_view

  import SanctumWeb.Components.CardSideTile
  import SanctumWeb.HomebrewComponents

  alias Sanctum.Homebrew
  alias Sanctum.HomebrewImages
  alias SanctumWeb.HomebrewLive.Support

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
         |> assign(:chooser_open?, false)
         |> assign(:pending, [])
         |> reset_assign()
         |> assign_cards()
         |> Support.assign_alts()
         |> allow_upload(:card_images,
           accept: ~w(.png .jpg .jpeg .webp),
           max_entries: 30,
           max_file_size: 20_000_000,
           auto_upload: true,
           progress: &handle_progress/3
         )
         |> allow_upload(:alt_images,
           accept: ~w(.png .jpg .jpeg .webp),
           max_entries: 30,
           max_file_size: 20_000_000,
           auto_upload: true,
           progress: &handle_progress/3
         )}

      {:error, _not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found.")
         |> push_navigate(to: ~p"/homebrew")}
    end
  end

  # -- Upload: auto-consumed as each entry finishes ---------------------------

  # `path` below is a LiveView-owned temp-upload path, not user input (Sobelow
  # Traversal false positive, ignored project-wide).

  defp handle_progress(:card_images, entry, socket) do
    if entry.done?, do: consume_card(socket, entry), else: {:noreply, socket}
  end

  defp handle_progress(:alt_images, entry, socket) do
    if entry.done?, do: consume_alt(socket, entry), else: {:noreply, socket}
  end

  defp consume_card(socket, entry) do
    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        {:ok, store_card(path, entry, socket.assigns.project, socket.assigns.current_user)}
      end)

    socket = socket |> assign(:chooser_open?, false) |> assign_cards()

    case result do
      {:ok, _card} ->
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not add #{entry.client_name}.")}
    end
  end

  defp consume_alt(socket, entry) do
    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        {:ok, HomebrewImages.store(File.read!(path), entry.client_type)}
      end)

    case result do
      {:ok, url} ->
        pending = %{
          id: System.unique_integer([:positive]),
          image_url: url,
          filename: entry.client_name
        }

        {:noreply,
         socket |> assign(:chooser_open?, false) |> update(:pending, &(&1 ++ [pending]))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not upload #{entry.client_name}.")}
    end
  end

  defp store_card(path, entry, project, user) do
    with {:ok, body} <- File.read(path),
         {:ok, url} <- HomebrewImages.store(body, entry.client_type) do
      Homebrew.create_custom_card(
        %{
          homebrew_project_id: project.id,
          card_sides: [%{image_url: url, filename: entry.client_name}]
        },
        user
      )
    end
  end

  # -- Chooser / validation ---------------------------------------------------

  @impl true
  def handle_event("open_chooser", _params, socket) do
    {:noreply, assign(socket, :chooser_open?, true)}
  end

  def handle_event("close_chooser", _params, socket) do
    {:noreply, assign(socket, :chooser_open?, false)}
  end

  # auto_upload still fires the form's phx-change; nothing to validate.
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  # -- Cards ------------------------------------------------------------------

  def handle_event("delete_card", %{"id" => id}, socket) do
    case Homebrew.destroy_custom_card(id, socket.assigns.current_user) do
      :ok -> {:noreply, assign_cards(socket)}
      _error -> {:noreply, put_flash(socket, :error, "Could not delete the card.")}
    end
  end

  # -- Alt art: pending assignment --------------------------------------------

  def handle_event("remove_pending", %{"id" => id}, socket) do
    id = String.to_integer(id)
    {:noreply, assign(socket, :pending, Enum.reject(socket.assigns.pending, &(&1.id == id)))}
  end

  def handle_event("open_assign", %{"id" => id}, socket) do
    id = String.to_integer(id)

    case Enum.find(socket.assigns.pending, &(&1.id == id)) do
      nil -> {:noreply, socket}
      pending -> {:noreply, socket |> reset_assign() |> assign(:assign_pending, pending)}
    end
  end

  def handle_event("close_assign", _params, socket) do
    {:noreply, reset_assign(socket)}
  end

  def handle_event("alt_search", %{"q" => q}, socket) do
    {:noreply,
     socket
     |> assign(:alt_search, q)
     |> assign(:alt_results, Support.search_official_sides(q, socket.assigns.current_user))}
  end

  def handle_event("pick_alt_target", %{"id" => id}, socket) do
    target = Enum.find(socket.assigns.alt_results, &(&1.id == id))
    {:noreply, assign(socket, :alt_target, target)}
  end

  def handle_event("clear_alt_target", _params, socket) do
    {:noreply, assign(socket, :alt_target, nil)}
  end

  def handle_event("create_alt", params, socket) do
    %{assign_pending: pending, alt_target: target, current_user: user, project: project} =
      socket.assigns

    with %{} <- pending,
         %{} <- target,
         {:ok, _alt} <-
           Homebrew.create_alt_art(
             %{
               homebrew_project_id: project.id,
               image_url: pending.image_url,
               target_card_id: target.card_id,
               side_identifier: target.side_identifier,
               artist: presence(params["artist"])
             },
             user
           ) do
      {:noreply,
       socket
       |> assign(:pending, Enum.reject(socket.assigns.pending, &(&1.id == pending.id)))
       |> reset_assign()
       |> Support.assign_alts()
       |> put_flash(:info, "Alt art added for #{target.name}.")}
    else
      _missing_or_error ->
        {:noreply, put_flash(socket, :error, "Could not add the alt art.")}
    end
  end

  def handle_event("revert_alt", %{"id" => id}, socket) do
    case Homebrew.revert_alt_art(id, socket.assigns.current_user) do
      {:ok, _new_card} ->
        {:noreply,
         socket
         |> assign_cards()
         |> Support.assign_alts()
         |> put_flash(:info, "Converted back to a card.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not revert the alt art.")}
    end
  end

  def handle_event("delete_alt", %{"id" => id}, socket) do
    {:noreply, Support.delete_alt(socket, id)}
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

  # -- Helpers ----------------------------------------------------------------

  defp reset_assign(socket) do
    socket
    |> assign(:assign_pending, nil)
    |> assign(:alt_search, "")
    |> assign(:alt_results, [])
    |> assign(:alt_target, nil)
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

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(_value), do: nil

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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:homebrew}>
      <.header>
        {@project.name}
        <:actions>
          <.button variant="primary" phx-click="open_chooser">Upload</.button>
        </:actions>
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

      <div :if={@pending != []} class="mb-8 border-2 border-primary/60 bg-base-200 p-4">
        <h2 class="mb-3 font-ibm-mono text-xs uppercase tracking-[0.2em] text-primary">
          To assign ({length(@pending)}) — pick the official card each re-imagines
        </h2>
        <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
          <div :for={item <- @pending} class="flex flex-col gap-2">
            <div class="aspect-[5/7] overflow-hidden border-2 border-neutral bg-base-300">
              <img src={item.image_url} alt={item.filename} class="h-full w-full object-cover" />
            </div>
            <div class="flex items-center gap-2">
              <.button
                variant="primary"
                phx-click="open_assign"
                phx-value-id={item.id}
                class="flex-1 px-2 py-1"
              >
                Assign
              </.button>
              <button
                type="button"
                phx-click="remove_pending"
                phx-value-id={item.id}
                aria-label="Remove"
                class="cursor-pointer border-2 border-neutral px-2 py-1 font-barlow-condensed text-xs font-bold uppercase tracking-[0.06em] text-base-content/60 hover:text-base-content"
              >
                &times;
              </button>
            </div>
          </div>
        </div>
      </div>

      <div :if={single_sided_count(@cards) >= 2} class="mb-3 flex items-center gap-3">
        <.button phx-click="toggle_pair_mode">
          {(@pair_mode? && "Cancel pairing") || "Pair fronts & backs"}
        </.button>
        <span :if={@pair_mode?} class="font-barlow-condensed text-sm text-base-content/60">
          Tap two cards to pair them as one two-sided card.
        </span>
      </div>

      <div
        :if={@cards == [] and @project_alts == [] and @pending == []}
        class="border-2 border-dashed border-neutral p-10 text-center"
      >
        <p class="font-barlow-condensed text-base-content/60">
          Nothing here yet — use <span class="font-bold text-base-content">Upload</span>
          to add cards or alt art.
        </p>
      </div>

      <div
        :if={@card_tiles != []}
        class="grid grid-cols-1 items-start gap-[18px] pb-28 sm:grid-cols-[repeat(auto-fill,minmax(452px,1fr))]"
      >
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
                  phx-click={open_confirm("confirm-del-card-#{card.id}")}
                  class="px-3 py-1.5 text-error hover:text-error"
                >
                  Delete
                </.button>
                <.confirm_dialog
                  :if={!@pair_mode?}
                  id={"confirm-del-card-#{card.id}"}
                  message="Delete this card?"
                  confirm_label="Delete card"
                  phx-click="delete_card"
                  phx-value-id={card.id}
                />
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

      <.alt_art_section
        alt_tiles={@alt_tiles}
        count={length(@project_alts)}
        revert?={true}
        class="mt-8"
      />

      <.pair_strip
        :if={@pair_mode? && length(@pair_selection) == 2}
        pair_selection={@pair_selection}
        cards={@cards}
      />

      <.upload_chooser
        open?={@chooser_open?}
        uploads_configured?={@uploads_configured?}
        card_upload={@uploads.card_images}
        alt_upload={@uploads.alt_images}
      />

      <.assign_sheet
        assign_pending={@assign_pending}
        alt_search={@alt_search}
        alt_results={@alt_results}
        alt_target={@alt_target}
      />
    </Layouts.app>
    """
  end

  # The Upload type chooser (the app's sheet shell recipe): each option is a
  # <label> wrapping a hidden auto-upload file input, so choosing a type opens
  # the OS picker in the same click. The inputs stay in the DOM even when the
  # sheet is hidden (transform + inert), so in-flight uploads survive closing.
  attr :open?, :boolean, required: true
  attr :uploads_configured?, :boolean, required: true
  attr :card_upload, :any, required: true
  attr :alt_upload, :any, required: true

  defp upload_chooser(assigns) do
    ~H"""
    <div
      :if={@open?}
      phx-click="close_chooser"
      phx-window-keydown="close_chooser"
      phx-key="escape"
      aria-hidden="true"
      class="fixed inset-0 z-40 bg-black/60"
    >
    </div>
    <section
      id="upload-chooser-sheet"
      phx-hook="PaneDrag"
      data-dismiss-event="close_chooser"
      role="dialog"
      aria-modal="true"
      aria-label="Upload"
      inert={!@open?}
      class={[
        "fixed inset-x-0 bottom-0 z-50 flex max-h-[85dvh] flex-col border-t-2 border-neutral bg-base-100",
        "transition-transform duration-200",
        "sm:inset-x-auto sm:bottom-auto sm:left-1/2 sm:top-[12dvh] sm:max-h-[80dvh] sm:w-[520px]",
        "sm:-translate-x-1/2 sm:border-2 sm:shadow-comic sm:transition-none",
        (@open? && "translate-y-0") || "translate-y-full sm:hidden"
      ]}
    >
      <button
        type="button"
        data-drag-handle
        data-haptic
        class="flex w-full flex-none cursor-grab touch-none items-center justify-center gap-2 py-3 text-base-content/50 sm:hidden"
        title="Close"
      >
        <span class="h-1 w-10 rounded-full bg-base-content/25"></span>
        <.icon name="hero-chevron-down" class="size-4" />
      </button>

      <header class="hidden flex-none items-center justify-between border-b-2 border-line px-5 py-3 sm:flex">
        <h2 class="font-bangers text-[22px] tracking-[0.02em] text-primary">What are you adding?</h2>
        <button
          type="button"
          phx-click="close_chooser"
          aria-label="Close"
          class="grid size-8 cursor-pointer place-items-center text-base-content/50 hover:text-white"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </header>

      <div class="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-4 py-4 sm:px-5">
        <.upload_unconfigured_notice :if={!@uploads_configured?} />

        <form :if={@uploads_configured?} id="homebrew-uploads" phx-change="validate">
          <div class="flex flex-col gap-3">
            <label class="group flex cursor-pointer items-center gap-4 border-2 border-neutral bg-base-200 p-4 transition-colors hover:border-primary">
              <.live_file_input upload={@card_upload} class="sr-only" />
              <.icon name="hero-rectangle-stack" class="size-7 shrink-0 text-primary" />
              <span class="min-w-0">
                <span class="block font-barlow-condensed text-base font-bold uppercase tracking-[0.05em]">
                  Cards
                </span>
                <span class="block font-barlow-condensed text-sm text-base-content/60">
                  Custom cards — each image becomes a card.
                </span>
              </span>
            </label>

            <label class="group flex cursor-pointer items-center gap-4 border-2 border-neutral bg-base-200 p-4 transition-colors hover:border-primary">
              <.live_file_input upload={@alt_upload} class="sr-only" />
              <.icon name="hero-photo" class="size-7 shrink-0 text-primary" />
              <span class="min-w-0">
                <span class="block font-barlow-condensed text-base font-bold uppercase tracking-[0.05em]">
                  Alt art
                </span>
                <span class="block font-barlow-condensed text-sm text-base-content/60">
                  New art for official cards — assign each image to a card.
                </span>
              </span>
            </label>
          </div>
        </form>

        <p class="mt-1 font-barlow-condensed text-xs text-base-content/40">
          More content types (heroes, scenarios, modular sets) are coming.
        </p>
      </div>
    </section>
    """
  end

  # The assignment bottom sheet: search an official card, pick a printed side,
  # credit the artist, create the alt. Openness keys off @assign_pending.
  attr :assign_pending, :any, required: true
  attr :alt_search, :string, required: true
  attr :alt_results, :list, required: true
  attr :alt_target, :any, required: true

  defp assign_sheet(assigns) do
    ~H"""
    <div
      :if={@assign_pending}
      phx-click="close_assign"
      phx-window-keydown="close_assign"
      phx-key="escape"
      aria-hidden="true"
      class="fixed inset-0 z-40 bg-black/60"
    >
    </div>
    <section
      id="assign-alt-sheet"
      phx-hook="PaneDrag"
      data-dismiss-event="close_assign"
      role="dialog"
      aria-modal="true"
      aria-label="Assign alt art"
      inert={is_nil(@assign_pending)}
      class={[
        "fixed inset-x-0 bottom-0 z-50 flex max-h-[85dvh] flex-col border-t-2 border-neutral bg-base-100",
        "transition-transform duration-200",
        "sm:inset-x-auto sm:bottom-auto sm:left-1/2 sm:top-[7dvh] sm:max-h-[86dvh] sm:w-[560px]",
        "sm:-translate-x-1/2 sm:border-2 sm:shadow-comic sm:transition-none",
        (@assign_pending && "translate-y-0") || "translate-y-full sm:hidden"
      ]}
    >
      <button
        type="button"
        data-drag-handle
        data-haptic
        class="flex w-full flex-none cursor-grab touch-none items-center justify-center gap-2 py-3 text-base-content/50 sm:hidden"
        title="Close"
      >
        <span class="h-1 w-10 rounded-full bg-base-content/25"></span>
        <.icon name="hero-chevron-down" class="size-4" />
      </button>

      <header class="hidden flex-none items-center justify-between border-b-2 border-line px-5 py-3 sm:flex">
        <h2 class="font-bangers text-[22px] tracking-[0.02em] text-primary">Assign Alt Art</h2>
        <button
          type="button"
          phx-click="close_assign"
          aria-label="Close"
          class="grid size-8 cursor-pointer place-items-center text-base-content/50 hover:text-white"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </header>

      <div :if={@assign_pending} class="min-h-0 flex-1 overflow-y-auto px-4 py-4 sm:px-5">
        <div class="mb-4 flex items-center gap-3">
          <div class="aspect-[5/7] w-16 shrink-0 overflow-hidden border-2 border-neutral">
            <img src={@assign_pending.image_url} alt="alt art" class="h-full w-full object-cover" />
          </div>
          <p class="font-barlow-condensed text-[14px] text-base-content/70">
            Pick the official card this art re-imagines. It appears as fan art on that
            card's page; your image is never a new card.
          </p>
        </div>

        <div :if={is_nil(@alt_target)} id="alt-search-nav" phx-hook="AltSearchNav">
          <%!-- The hook (mounted when this appears) focuses the input and drives
               ArrowUp/Down + Enter over the [data-alt-result] buttons below. --%>
          <form id="assign-alt-search" phx-change="alt_search" onsubmit="return false">
            <.input
              type="text"
              name="q"
              value={@alt_search}
              label="Official card"
              placeholder="Search by name…"
              autocomplete="off"
              phx-debounce="250"
            />
          </form>

          <div class="mt-3 flex flex-col">
            <button
              :for={side <- @alt_results}
              type="button"
              data-alt-result
              phx-click="pick_alt_target"
              phx-value-id={side.id}
              class="flex cursor-pointer items-center gap-3 border-b border-neutral/40 py-2 text-left hover:bg-base-200"
            >
              <div class="aspect-[5/7] w-10 shrink-0 overflow-hidden border border-neutral">
                <img
                  :if={side.image_url}
                  src={side.image_url}
                  alt={side.name}
                  loading="lazy"
                  class="h-full w-full object-cover"
                />
              </div>
              <span class="min-w-0 flex-1 truncate font-barlow-condensed text-[14px] font-bold uppercase tracking-[0.04em]">
                {side.name}
              </span>
              <span class="shrink-0 font-ibm-mono text-[11px] text-base-content/50">
                {side.code}<span :if={side.card && side.card.pack}> · {side.card.pack}</span>
              </span>
            </button>
          </div>
        </div>

        <div :if={@alt_target} class="flex flex-col gap-4">
          <div class="flex items-center justify-between gap-3 border-2 border-neutral bg-base-200 px-3 py-2">
            <span class="font-barlow-condensed text-[14px] font-bold uppercase tracking-[0.04em]">
              Alt art for {@alt_target.name}
              <span class="font-ibm-mono text-[11px] font-normal text-base-content/50">
                ({@alt_target.code})
              </span>
            </span>
            <button
              type="button"
              phx-click="clear_alt_target"
              class="shrink-0 cursor-pointer font-barlow-condensed text-[13px] font-bold uppercase tracking-[0.08em] text-base-content/60 hover:text-base-content"
            >
              Change
            </button>
          </div>

          <form
            id="assign-alt-form"
            phx-hook="AutoFocus"
            phx-submit="create_alt"
            class="flex flex-col gap-4"
          >
            <.input
              type="text"
              name="artist"
              value=""
              label="Artist credit (optional)"
              autocomplete="off"
            />
            <.button variant="primary" type="submit" class="self-end">
              Add alt art
            </.button>
          </form>
        </div>
      </div>
    </section>
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
