defmodule SanctumWeb.HomebrewLive.EditCard do
  @moduledoc """
  Full-page editor for one custom card: card-level flags plus per-side
  metadata, each side's fields laid out beside that side's art (double-sided
  cards get one section per face). Changes autosave on a debounce — there is
  no Save button, just a save-state indicator; invalid input (e.g. a blanked
  name) shows inline errors and simply doesn't persist until fixed. Also
  hosts the card-shape actions — split a two-sided card, or declare a
  single-sided one as alt art for an official card (a bottom sheet, never a
  modal). Nothing else is ever required; blank stays blank.
  """

  use SanctumWeb, :live_view

  alias Sanctum.Games.Stat
  alias Sanctum.Homebrew
  alias SanctumWeb.Components.Card, as: CardComponents

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"id" => project_id, "card_id" => card_id}, _session, socket) do
    with {:ok, project} <- Homebrew.get_project(project_id, actor: socket.assigns.current_user),
         {:ok, card} <- fetch_card(card_id, project, socket.assigns.current_user) do
      {:ok,
       socket
       |> assign(:project, project)
       |> assign(:alt_search, "")
       |> assign(:alt_results, [])
       |> assign(:alt_target, nil)
       |> assign(:alt_declare?, false)
       |> assign(:save_state, :pristine)
       |> assign_card(card)}
    else
      {:error, _not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Card not found.")
         |> push_navigate(to: ~p"/homebrew")}
    end
  end

  defp fetch_card(card_id, project, actor) do
    case Ash.get(Sanctum.Games.Card, card_id, actor: actor, load: [:card_sides, :primary_side]) do
      {:ok, %{homebrew_project_id: project_id} = card} when project_id == project.id ->
        {:ok, card}

      _other_project_or_error ->
        {:error, :not_found}
    end
  end

  defp assign_card(socket, card) do
    form =
      AshPhoenix.Form.for_update(card, :update_custom,
        as: "card",
        actor: socket.assigns.current_user
      )

    name = (card.primary_side && card.primary_side.name) || "Card"

    socket
    |> assign(:card, card)
    |> assign(:page_title, "Edit #{name}")
    |> assign(:form, to_form(form))
  end

  # Autosave: every (input-debounced) change submits the form. Success
  # rebuilds the form from the persisted card — the rendered values equal
  # what was just typed, so focused inputs are untouched; failure keeps the
  # errored form on screen and nothing persists until it's fixed. The
  # phx-submit route (Enter in a field) lands here too.
  @impl true
  def handle_event(event, %{"card" => params}, socket) when event in ["validate", "save"] do
    params = splice_traits(params)

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, card} ->
        card = Ash.load!(card, [:card_sides, :primary_side], actor: socket.assigns.current_user)

        {:noreply,
         socket
         |> assign_card(card)
         |> assign(:save_state, :saved)}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> assign(:save_state, :error)}
    end
  end

  def handle_event("unpair_card", _params, socket) do
    case Homebrew.unpair_custom_card(socket.assigns.card.id, socket.assigns.current_user) do
      {:ok, {_updated, _new_card}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Card split into two.")
         |> push_navigate(to: ~p"/homebrew/#{socket.assigns.project.id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not split the card.")}
    end
  end

  # -- Alt art ---------------------------------------------------------------

  def handle_event("open_declare_alt", _params, socket) do
    if socket.assigns.card.is_multi_sided do
      {:noreply, socket}
    else
      {:noreply, socket |> reset_alt_declare() |> assign(:alt_declare?, true)}
    end
  end

  def handle_event("close_declare_alt", _params, socket) do
    {:noreply, reset_alt_declare(socket)}
  end

  def handle_event("alt_search", %{"q" => q}, socket) do
    {:noreply,
     socket
     |> assign(:alt_search, q)
     |> assign(:alt_results, search_official_sides(q, socket.assigns.current_user))}
  end

  def handle_event("pick_alt_target", %{"id" => id}, socket) do
    target = Enum.find(socket.assigns.alt_results, &(&1.id == id))
    {:noreply, assign(socket, :alt_target, target)}
  end

  def handle_event("clear_alt_target", _params, socket) do
    {:noreply, assign(socket, :alt_target, nil)}
  end

  def handle_event("declare_alt", params, socket) do
    %{card: card, alt_target: target, current_user: user} = socket.assigns

    with %{} <- target,
         {:ok, _alt} <-
           Homebrew.declare_alt_art(
             card.id,
             target.card_id,
             [artist: presence(params["artist"]), side_identifier: target.side_identifier],
             user
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Declared as alt art for #{target.name}.")
       |> push_navigate(to: ~p"/homebrew/#{socket.assigns.project.id}")}
    else
      _missing_or_error ->
        {:noreply, put_flash(socket, :error, "Could not declare the alt art.")}
    end
  end

  # -- Helpers -----------------------------------------------------------------

  defp reset_alt_declare(socket) do
    socket
    |> assign(:alt_declare?, false)
    |> assign(:alt_search, "")
    |> assign(:alt_results, [])
    |> assign(:alt_target, nil)
  end

  # Official-card picker for the declare sheet: the shared :browse search
  # (name/subname + query syntax) pinned to the official catalog — the
  # actor's own customs must not be targetable.
  defp search_official_sides(q, actor) do
    if is_binary(q) and String.trim(q) != "" do
      require Ash.Query

      Sanctum.Games.CardSide
      |> Ash.Query.for_read(:browse, %{query: q}, actor: actor)
      |> Ash.Query.filter(card.origin == :official)
      |> Ash.read!(actor: actor, page: [limit: 10])
      |> Map.get(:results)
    else
      []
    end
  end

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(_value), do: nil

  # The persisted side struct backing a nested side form — pairs each
  # fieldset with its own art.
  defp side_struct(card, side_form) do
    id = side_form[:id].value
    Enum.find(card.card_sides, &(&1.id == id))
  end

  defp side_frame_class(%{type: type}) do
    if CardComponents.landscape_type?(type) do
      "aspect-[7/5] w-full max-w-[300px]"
    else
      "aspect-[5/7] w-full max-w-[220px]"
    end
  end

  defp side_frame_class(_side), do: "aspect-[5/7] w-full max-w-[220px]"

  defp save_state_label(:pristine), do: "Changes save automatically"
  defp save_state_label(:saved), do: "All changes saved"
  defp save_state_label(:error), do: "Not saved — fix the errors above"

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

  defp enum_options(enum_module) do
    Enum.map(enum_module.values(), &{Phoenix.Naming.humanize(&1), to_string(&1)})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:homebrew}>
      <div class="mb-3">
        <.link
          navigate={~p"/homebrew/#{@project.id}"}
          class="font-barlow-condensed text-sm font-bold uppercase tracking-[0.08em] text-base-content/60 hover:text-primary"
        >
          ← {@project.name}
        </.link>
      </div>

      <.header>
        {(@card.primary_side && @card.primary_side.name) || "Edit Card"}
      </.header>

      <.form
        for={@form}
        id={"edit-card-form-#{@card.id}"}
        phx-change="validate"
        phx-submit="save"
        class="flex max-w-4xl flex-col gap-6"
      >
        <.panel class="p-5">
          <h3 class="mb-3 font-anton text-sm uppercase tracking-[0.08em] text-base-content/45">
            Card
          </h3>
          <div class="grid max-w-md grid-cols-2 gap-3">
            <.input field={@form[:deck_limit]} type="number" label="Deck limit" phx-debounce="500" />
            <div class="self-end pb-1">
              <.input field={@form[:unique]} type="checkbox" label="Unique" />
            </div>
          </div>
        </.panel>

        <.inputs_for :let={side} field={@form[:card_sides]}>
          <.panel class="p-5">
            <h3
              :if={@card.is_multi_sided}
              class="mb-3 font-anton text-sm uppercase tracking-[0.08em] text-base-content/45"
            >
              Side {String.upcase(side[:side_identifier].value || "")}
            </h3>

            <div class="flex flex-col gap-6 sm:flex-row sm:items-start">
              <div
                :if={side_struct(@card, side) && side_struct(@card, side).image_url}
                class={[
                  "shrink-0 self-center overflow-hidden border-2 border-neutral shadow-comic-sm sm:self-start",
                  side_frame_class(side_struct(@card, side))
                ]}
              >
                <img
                  src={side_struct(@card, side).image_url}
                  alt={side[:name].value || "card art"}
                  class="h-full w-full object-cover"
                />
              </div>

              <div class="flex min-w-0 flex-1 flex-col gap-3">
                <div class="grid grid-cols-2 gap-3">
                  <.input field={side[:name]} type="text" label="Name" phx-debounce="500" />
                  <.input field={side[:subname]} type="text" label="Subname" phx-debounce="500" />
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
                  <.input field={side[:cost]} type="number" label="Cost" phx-debounce="500" />
                </div>

                <%!-- Full stat axes: value, ★ (a star effect relates to the
                     stat), consequential damage (atk/thw/def), and health
                     scaling. Nested-map params cast through Stat.cast_input;
                     all-blank rows collapse back to an absent stat. --%>
                <div class="flex max-w-md flex-col gap-2">
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
                  <%!-- A villain/minion's scheme power — flat integer +
                       boolean columns (the boost/boost_star shape), so it
                       takes field inputs rather than the nested-map stat
                       row. --%>
                  <div class="grid grid-cols-[42px_1fr_52px_1fr] items-center gap-2">
                    <span class={stat_col_label_class()}>SCH</span>
                    <.input
                      field={side[:scheme]}
                      type="number"
                      aria-label="scheme power"
                      phx-debounce="500"
                    />
                    <div class="flex justify-center">
                      <.input
                        field={side[:scheme_star]}
                        type="checkbox"
                        aria-label="scheme star effect"
                      />
                    </div>
                    <span></span>
                  </div>
                  <.stat_row form={side} stat={:defense} label="DEF" consequential />
                  <.stat_row form={side} stat={:health} label="HP" scaling />
                  <.stat_row form={side} stat={:recover} label="REC" />
                </div>
                <.input
                  type="text"
                  name={side.name <> "[traits_string]"}
                  label="Traits (comma-separated)"
                  value={traits_value(side)}
                  phx-debounce="500"
                />
                <.input field={side[:text]} type="textarea" label="Text" phx-debounce="600" />
                <.input field={side[:flavor]} type="textarea" label="Flavor" phx-debounce="600" />
              </div>
            </div>
          </.panel>
        </.inputs_for>

        <div class="flex items-center gap-3 pb-16">
          <button
            :if={@card.is_multi_sided}
            type="button"
            phx-click="unpair_card"
            data-confirm="Split this card into two single-sided cards?"
            class="font-barlow-condensed text-sm font-bold uppercase tracking-[0.08em] text-error/80 hover:text-error"
          >
            Split into two cards
          </button>
          <button
            :if={!@card.is_multi_sided}
            type="button"
            phx-click="open_declare_alt"
            class="font-barlow-condensed text-sm font-bold uppercase tracking-[0.08em] text-base-content/60 hover:text-base-content"
          >
            Use as alt art…
          </button>
          <span
            class={[
              "ml-auto font-barlow-condensed text-sm font-bold uppercase tracking-[0.08em]",
              (@save_state == :error && "text-error") || "text-base-content/45"
            ]}
            role="status"
          >
            {save_state_label(@save_state)}
          </span>
        </div>
      </.form>

      <.declare_alt_sheet
        alt_declare?={@alt_declare?}
        card={@card}
        alt_search={@alt_search}
        alt_results={@alt_results}
        alt_target={@alt_target}
      />
    </Layouts.app>
    """
  end

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
      <.input
        type="number"
        name={@base <> "[value]"}
        value={Stat.input_value(@current)}
        phx-debounce="500"
      />
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
        phx-debounce="500"
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

  # The declare-alt bottom sheet (the app's sheet shell recipe): search an
  # official card, pick a printed side, credit the artist, convert. Openness
  # keys off @alt_declare?.
  defp declare_alt_sheet(assigns) do
    ~H"""
    <div
      :if={@alt_declare?}
      phx-click="close_declare_alt"
      phx-window-keydown="close_declare_alt"
      phx-key="escape"
      aria-hidden="true"
      class="fixed inset-0 z-40 bg-black/60"
    >
    </div>
    <section
      id="declare-alt-sheet"
      phx-hook="PaneDrag"
      data-dismiss-event="close_declare_alt"
      role="dialog"
      aria-modal="true"
      aria-label="Use as alt art"
      inert={!@alt_declare?}
      class={[
        "fixed inset-x-0 bottom-0 z-50 flex max-h-[85dvh] flex-col border-t-2 border-neutral bg-base-100",
        "transition-transform duration-200",
        "sm:inset-x-auto sm:bottom-auto sm:left-1/2 sm:top-[7dvh] sm:max-h-[86dvh] sm:w-[560px]",
        "sm:-translate-x-1/2 sm:border-2 sm:shadow-comic sm:transition-none",
        (@alt_declare? && "translate-y-0") || "translate-y-full sm:hidden"
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
        <h2 class="font-bangers text-[22px] tracking-[0.02em] text-primary">Use as Alt Art</h2>
        <button
          type="button"
          phx-click="close_declare_alt"
          aria-label="Close"
          class="grid size-8 cursor-pointer place-items-center text-base-content/50 hover:text-white"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </header>

      <div :if={@alt_declare?} class="min-h-0 flex-1 overflow-y-auto px-4 py-4 sm:px-5">
        <div class="mb-4 flex items-center gap-3">
          <div class="aspect-[5/7] w-16 shrink-0 overflow-hidden border-2 border-neutral">
            <img
              :if={@card.primary_side && @card.primary_side.image_url}
              src={@card.primary_side.image_url}
              alt="custom card art"
              class="h-full w-full object-cover"
            />
          </div>
          <p class="font-barlow-condensed text-[14px] text-base-content/70">
            Declare this image as alternate art for an official card. It leaves your
            card list (any card details are discarded) and appears on that card's page.
          </p>
        </div>

        <form :if={is_nil(@alt_target)} phx-change="alt_search" onsubmit="return false">
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

        <div :if={is_nil(@alt_target)} class="mt-3 flex flex-col">
          <button
            :for={side <- @alt_results}
            type="button"
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

          <form phx-submit="declare_alt" class="flex flex-col gap-4">
            <.input
              type="text"
              name="artist"
              value=""
              label="Artist credit (optional)"
              autocomplete="off"
            />
            <.button variant="primary" type="submit" class="self-end">
              Declare alt art
            </.button>
          </form>
        </div>
      </div>
    </section>
    """
  end
end
