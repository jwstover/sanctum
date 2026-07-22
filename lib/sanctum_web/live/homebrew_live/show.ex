defmodule SanctumWeb.HomebrewLive.Show do
  @moduledoc """
  A homebrew project page: drag-drop image upload, the project's cards as an
  art grid, per-card enrichment (a bottom sheet — never a modal — editing
  optional metadata), and front/back pairing of two single-sided cards.
  Every uploaded image immediately becomes a playable custom card; metadata
  is progressive and never required.
  """

  use SanctumWeb, :live_view

  alias Sanctum.Games.Stat
  alias Sanctum.Homebrew
  alias Sanctum.HomebrewImages
  alias SanctumWeb.Components.Card, as: CardComponents

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
         |> assign(:editing_card, nil)
         |> assign(:enrich_form, nil)
         |> assign(:pair_mode?, false)
         |> assign(:pair_selection, [])
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

  # -- Enrichment sheet -----------------------------------------------------

  def handle_event("edit_card", %{"id" => id}, socket) do
    case Ash.get(Sanctum.Games.Card, id,
           actor: socket.assigns.current_user,
           load: [:card_sides]
         ) do
      {:ok, card} ->
        form =
          AshPhoenix.Form.for_update(card, :update_custom,
            as: "card",
            actor: socket.assigns.current_user
          )

        {:noreply,
         socket
         |> assign(:editing_card, card)
         |> assign(:enrich_form, to_form(form))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Card not found.")}
    end
  end

  def handle_event("close_enrichment", _params, socket) do
    {:noreply, socket |> assign(:editing_card, nil) |> assign(:enrich_form, nil)}
  end

  def handle_event("enrich_validate", %{"card" => params}, socket) do
    params = splice_traits(params)

    {:noreply,
     assign(socket, :enrich_form, AshPhoenix.Form.validate(socket.assigns.enrich_form, params))}
  end

  def handle_event("enrich_save", %{"card" => params}, socket) do
    params = splice_traits(params)

    case AshPhoenix.Form.submit(socket.assigns.enrich_form, params: params) do
      {:ok, _card} ->
        {:noreply,
         socket
         |> assign(:editing_card, nil)
         |> assign(:enrich_form, nil)
         |> assign_cards()
         |> put_flash(:info, "Card updated.")}

      {:error, form} ->
        {:noreply, assign(socket, :enrich_form, form)}
    end
  end

  def handle_event("unpair_card", %{"id" => id}, socket) do
    case Homebrew.unpair_custom_card(id, socket.assigns.current_user) do
      {:ok, {_updated, _new_card}} ->
        {:noreply,
         socket
         |> assign(:editing_card, nil)
         |> assign(:enrich_form, nil)
         |> assign_cards()
         |> put_flash(:info, "Card split into two.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not split the card.")}
    end
  end

  # -- Pairing --------------------------------------------------------------

  def handle_event("toggle_pair_mode", _params, socket) do
    {:noreply,
     socket
     |> assign(:pair_mode?, !socket.assigns.pair_mode?)
     |> assign(:pair_selection, [])
     |> assign(:editing_card, nil)
     |> assign(:enrich_form, nil)}
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

    assign(socket, :cards, cards)
  end

  # -- Form helpers -----------------------------------------------------------

  # Splices each side's comma-separated traits_string into the traits array.
  # Runs on validate AND submit so the traits input round-trips morphdom
  # re-renders (splicing only pre-submit reverts the input on every validate).
  defp splice_traits(%{"card_sides" => %{}} = params) do
    Map.update!(params, "card_sides", fn sides ->
      Map.new(sides, fn {index, side} -> {index, put_side_traits(side)} end)
    end)
  end

  defp splice_traits(params), do: params

  defp put_side_traits(%{"traits_string" => traits_string} = side) do
    traits =
      traits_string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    Map.put(side, "traits", traits)
  end

  defp put_side_traits(side), do: side

  defp traits_value(side_form) do
    side_form.params["traits_string"] ||
      case side_form[:traits].value do
        traits when is_list(traits) -> Enum.join(traits, ", ")
        traits when is_binary(traits) -> traits
        _ -> ""
      end
  end

  defp stat_col_label_class,
    do: "font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/60"

  # One editable stat: value + ★ + (consequential damage | health scaling).
  # Inputs are nested-map params (e.g. side[attack][consequential]) so
  # Stat.cast_input's map branch rebuilds the full struct on save.
  attr :form, Phoenix.HTML.Form, required: true
  attr :stat, :atom, required: true
  attr :label, :string, required: true
  attr :consequential, :boolean, default: false
  attr :scaling, :boolean, default: false

  defp stat_row(assigns) do
    assigns =
      assigns
      |> assign(:base, assigns.form.name <> "[#{assigns.stat}]")
      |> assign(:current, assigns.form[assigns.stat].value)

    ~H"""
    <div class="grid grid-cols-[42px_1fr_52px_1fr] items-center gap-2">
      <span class={stat_col_label_class()}>{@label}</span>
      <.input type="number" name={@base <> "[value]"} value={Stat.input_value(@current)} />
      <div class="flex justify-center">
        <.input
          type="checkbox"
          name={@base <> "[star]"}
          checked={Stat.input_star(@current)}
          aria-label={"#{@label} star effect"}
        />
      </div>
      <.input
        :if={@consequential}
        type="number"
        name={@base <> "[consequential]"}
        value={Stat.input_consequential(@current)}
        aria-label={"#{@label} consequential damage"}
      />
      <.input
        :if={@scaling}
        type="select"
        name={@base <> "[scaling]"}
        value={to_string(Stat.input_scaling(@current))}
        options={[{"Flat", "flat"}, {"Per player", "per_player"}, {"Per group", "per_group"}]}
        aria-label={"#{@label} scaling"}
      />
      <span :if={!@consequential && !@scaling}></span>
    </div>
    """
  end

  defp enum_options(enum_module) do
    Enum.map(enum_module.values(), &{Phoenix.Naming.humanize(&1), to_string(&1)})
  end

  defp tile_frame_class(card) do
    if CardComponents.landscape_type?(card.primary_side && card.primary_side.type) do
      "aspect-[88/63]"
    else
      "aspect-[63/88]"
    end
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
        {length(@cards)} {if length(@cards) == 1, do: "card", else: "cards"} &middot; {@project.visibility} &middot; unofficial fan content
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

      <div class="grid grid-cols-[repeat(auto-fill,minmax(110px,1fr))] gap-2.5 pb-28">
        <div :for={card <- @cards} class="group relative">
          <div class={[
            "border-2 border-neutral shadow-comic-sm",
            tile_frame_class(card),
            pair_role(card.id, @pair_selection) &&
              "outline outline-[3px] outline-primary -translate-y-0.5",
            @pair_mode? && card.is_multi_sided && "opacity-40"
          ]}>
            <.mc_card
              name={card.primary_side && card.primary_side.name}
              image_url={card.primary_side && card.primary_side.image_url}
              cost={card.primary_side && card.primary_side.cost}
              type={(card.primary_side && card.primary_side.type) || "event"}
              aspect={(card.primary_side && card.primary_side.aspect) || :hero}
              size="md"
            />
          </div>

          <button
            :if={!@pair_mode?}
            type="button"
            phx-click="edit_card"
            phx-value-id={card.id}
            aria-label={"Edit #{(card.primary_side && card.primary_side.name) || "card"}"}
            class="absolute inset-0 z-[3] cursor-pointer"
          ></button>
          <button
            :if={@pair_mode? && !card.is_multi_sided}
            type="button"
            phx-click="toggle_pair_select"
            phx-value-id={card.id}
            aria-label={"Select #{(card.primary_side && card.primary_side.name) || "card"} for pairing"}
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

          <button
            :if={!@pair_mode?}
            type="button"
            phx-click="delete_card"
            phx-value-id={card.id}
            data-confirm="Delete this card?"
            aria-label="delete card"
            class="absolute right-1 top-1 z-[4] hidden border-2 border-neutral bg-base-100/90 px-1.5 font-bold text-error group-hover:block"
          >
            &times;
          </button>
        </div>
      </div>

      <.pair_strip
        :if={@pair_mode? && length(@pair_selection) == 2}
        pair_selection={@pair_selection}
        cards={@cards}
      />

      <.enrichment_sheet editing_card={@editing_card} enrich_form={@enrich_form} />
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

  # The enrichment bottom sheet (filter_sheet's shell recipe): rendered once,
  # unconditionally, so the mobile slide-up transition works; openness keys
  # off @editing_card. All input values derive from @enrich_form so upload-
  # progress re-renders can't clobber in-flight edits.
  defp enrichment_sheet(assigns) do
    ~H"""
    <div
      :if={@editing_card}
      phx-click="close_enrichment"
      phx-window-keydown="close_enrichment"
      phx-key="escape"
      aria-hidden="true"
      class="fixed inset-0 z-40 bg-black/60"
    >
    </div>
    <section
      id="enrichment-sheet"
      phx-hook="PaneDrag"
      data-dismiss-event="close_enrichment"
      role="dialog"
      aria-modal="true"
      aria-label="Edit card"
      inert={!@editing_card}
      class={[
        "fixed inset-x-0 bottom-0 z-50 flex max-h-[85dvh] flex-col border-t-2 border-neutral bg-base-100",
        "transition-transform duration-200",
        "sm:inset-x-auto sm:bottom-auto sm:left-1/2 sm:top-[7dvh] sm:max-h-[86dvh] sm:w-[560px]",
        "sm:-translate-x-1/2 sm:border-2 sm:shadow-comic sm:transition-none",
        (@editing_card && "translate-y-0") || "translate-y-full sm:hidden"
      ]}
    >
      <button
        type="button"
        data-drag-handle
        data-haptic
        class="flex w-full flex-none cursor-grab touch-none items-center justify-center gap-2 py-3 text-base-content/50 sm:hidden"
        title="Close editor"
      >
        <span class="h-1 w-10 rounded-full bg-base-content/25"></span>
        <.icon name="hero-chevron-down" class="size-4" />
      </button>

      <header class="hidden flex-none items-center justify-between border-b-2 border-line px-5 py-3 sm:flex">
        <h2 class="font-bangers text-2xl tracking-[0.02em] text-primary">Edit Card</h2>
        <button
          type="button"
          phx-click="close_enrichment"
          aria-label="Close editor"
          class="grid size-8 cursor-pointer place-items-center text-base-content/50 hover:text-white"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </header>

      <.form
        :if={@enrich_form}
        for={@enrich_form}
        id={"enrichment-form-#{@editing_card.id}"}
        phx-change="enrich_validate"
        phx-submit="enrich_save"
        class="flex min-h-0 flex-1 flex-col"
      >
        <div class="min-h-0 flex-1 overflow-y-auto px-4 py-3 sm:px-5">
          <section class="mb-6">
            <h3 class="mb-2.5 font-anton text-sm uppercase tracking-[0.08em] text-base-content/45">
              Card
            </h3>
            <div class="grid grid-cols-2 gap-3">
              <.input field={@enrich_form[:deck_limit]} type="number" label="Deck limit" />
              <div class="self-end pb-1">
                <.input field={@enrich_form[:unique]} type="checkbox" label="Unique" />
              </div>
            </div>
          </section>

          <.inputs_for :let={side} field={@enrich_form[:card_sides]}>
            <section class="mb-6 border-t border-line/70 pt-4">
              <h3
                :if={@editing_card.is_multi_sided}
                class="mb-2.5 font-anton text-sm uppercase tracking-[0.08em] text-base-content/45"
              >
                Side {String.upcase(side[:side_identifier].value || "")}
              </h3>
              <div class="flex flex-col gap-3">
                <div class="grid grid-cols-2 gap-3">
                  <.input field={side[:name]} type="text" label="Name" />
                  <.input field={side[:subname]} type="text" label="Subname" />
                </div>
                <div class="grid grid-cols-3 gap-3">
                  <.input
                    field={side[:ownership]}
                    type="select"
                    label="Pool"
                    prompt="—"
                    options={enum_options(Sanctum.Games.CardOwnership)}
                  />
                  <.input
                    field={side[:type]}
                    type="select"
                    label="Type"
                    prompt="—"
                    options={enum_options(Sanctum.Games.CardType)}
                  />
                  <.input
                    field={side[:aspect]}
                    type="select"
                    label="Aspect"
                    prompt="—"
                    options={enum_options(Sanctum.Games.CardAspect)}
                  />
                </div>
                <p class="-mt-1 font-barlow-condensed text-xs text-base-content/45">
                  Schemes render landscape.
                </p>
                <div class="grid grid-cols-3 gap-3">
                  <.input field={side[:cost]} type="number" label="Cost" />
                </div>

                <%!-- Full stat axes: value, ★ (a star effect relates to the
                     stat), consequential damage (atk/thw/def), and health
                     scaling. Nested-map params cast through Stat.cast_input;
                     all-blank rows collapse back to an absent stat. --%>
                <div class="flex flex-col gap-2">
                  <div class="grid grid-cols-[42px_1fr_52px_1fr] items-end gap-2">
                    <span></span>
                    <span class={stat_col_label_class()}>Value</span>
                    <%!-- "s" is the ChampionsIcons star glyph (see stat_badge);
                         normal-case so the label style can't uppercase it into
                         a different glyph. --%>
                    <span
                      class="text-center font-champions text-sm normal-case text-base-content/60"
                      aria-label="star effect"
                    >
                      s
                    </span>
                    <span class={stat_col_label_class()}>Conseq. dmg</span>
                  </div>
                  <.stat_row form={side} stat={:attack} label="ATK" consequential />
                  <.stat_row form={side} stat={:thwart} label="THW" consequential />
                  <.stat_row form={side} stat={:defense} label="DEF" consequential />
                  <.stat_row form={side} stat={:health} label="HP" scaling />
                  <.stat_row form={side} stat={:recover} label="REC" />
                </div>
                <.input
                  type="text"
                  name={side.name <> "[traits_string]"}
                  label="Traits (comma-separated)"
                  value={traits_value(side)}
                />
                <.input field={side[:text]} type="textarea" label="Text" />
                <.input field={side[:flavor]} type="textarea" label="Flavor" />
              </div>
            </section>
          </.inputs_for>
        </div>

        <footer class="flex flex-none items-center gap-3 border-t-2 border-line bg-base-100 px-4 py-3 pb-[max(env(safe-area-inset-bottom),0.75rem)] sm:px-5">
          <button
            :if={@editing_card && @editing_card.is_multi_sided}
            type="button"
            phx-click="unpair_card"
            phx-value-id={@editing_card.id}
            data-confirm="Split this card into two single-sided cards?"
            class="font-barlow-condensed text-sm font-bold uppercase tracking-[0.08em] text-error/80 hover:text-error"
          >
            Split into two cards
          </button>
          <.button variant="primary" type="submit" class="ml-auto">Save</.button>
        </footer>
      </.form>
    </section>
    """
  end
end
