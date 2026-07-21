defmodule SanctumWeb.Components.FilterSheet do
  @moduledoc """
  The unified "Filters" surface for the browse pages: a `filter_button/1`
  trigger next to the search bar and a `filter_sheet/1` panel — a slide-up
  bottom sheet on mobile (drag-to-dismiss via the `PaneDrag` hook), a
  centered dialog on `sm+`.

  The sheet is a pure projection of the current query string: its controls
  are generated from the registry (`Sanctum.Search.FormSchema`) and their
  state is read out of `@query` (`Sanctum.Search.FormSync.read/2`) at render
  time. Every interaction submits the single wrapping form to `@on_change`;
  the host turns the payload back into a query string with
  `FormSync.fields_from_params/2` + `FormSync.update/3` and pushes it
  through its existing search path. Query text the form can't represent is
  preserved untouched and surfaced in an "Also filtering" row.
  """

  use Phoenix.Component

  import SanctumWeb.CoreComponents, only: [icon: 1, button: 1]

  alias Sanctum.Search.{FormSchema, FormSync}

  # Aspect chips carry the same color swatches as the old filter pills.
  # Literal class names so Tailwind sees them.
  @aspect_dots %{
    "hero" => "bg-aspect-hero",
    "aggression" => "bg-aspect-aggression",
    "justice" => "bg-aspect-justice",
    "leadership" => "bg-aspect-leadership",
    "protection" => "bg-aspect-protection",
    "pool" => "bg-aspect-pool",
    "basic" => "bg-aspect-basic"
  }

  @op_symbols %{eq: "=", neq: "≠", lt: "<", gt: ">", lte: "≤", gte: "≥"}

  @doc """
  The "Filters" trigger button, showing how many filters the current query
  expresses (`FormSync.active_count/2`).
  """
  attr :count, :integer, default: 0
  attr :on_toggle, :string, default: "toggle_filters"
  attr :class, :string, default: ""

  def filter_button(assigns) do
    ~H"""
    <.button type="button" phx-click={@on_toggle} class={@class}>
      <.icon name="hero-funnel" class="size-4" /> Filters
      <span
        :if={@count > 0}
        class="grid min-w-5 place-items-center bg-primary px-1 font-anton text-[12px] leading-5 text-primary-content"
      >
        {@count}
      </span>
    </.button>
    """
  end

  @doc """
  The filter sheet/dialog. Render it once per page, unconditionally — the
  mobile slide-up transition needs the element present in both states.

  The host owns all state: `@open?` (toggled by `@on_change`-style events),
  `@query` (the search string), and the events named by `@on_change` /
  `@on_toggle` / `@on_clear`.
  """
  attr :id, :string, required: true
  attr :open?, :boolean, required: true
  attr :query, :string, required: true
  attr :registry, :atom, doc: "Sanctum.Search.Registry module"
  attr :count, :integer, default: nil, doc: "filtered result count for the footer button"
  attr :on_change, :string, default: "filters_change"
  attr :on_toggle, :string, default: "toggle_filters"
  attr :on_clear, :string, default: "clear"
  attr :hide, :list, default: [], doc: "field names to omit (e.g. owned/mine when signed out)"

  slot :footer_extra, doc: "extra controls in the footer form (e.g. the deck browser's sort)"

  def filter_sheet(assigns) do
    assigns =
      assigns
      |> assign(:sync, FormSync.read(assigns.query, assigns.registry))
      |> assign(:groups, visible_groups(assigns.registry, assigns.hide))

    ~H"""
    <div
      :if={@open?}
      phx-click={@on_toggle}
      phx-window-keydown={@on_toggle}
      phx-key="escape"
      aria-hidden="true"
      class="fixed inset-0 z-40 bg-black/60"
    >
    </div>
    <section
      id={@id}
      phx-hook="PaneDrag"
      data-dismiss-event={@on_toggle}
      role="dialog"
      aria-modal="true"
      aria-label="Filters"
      inert={!@open?}
      class={[
        "fixed inset-x-0 bottom-0 z-50 flex max-h-[85dvh] flex-col border-t-2 border-neutral bg-base-100",
        "transition-transform duration-200",
        "sm:inset-x-auto sm:bottom-auto sm:left-1/2 sm:top-[7dvh] sm:max-h-[86dvh] sm:w-[560px]",
        "sm:-translate-x-1/2 sm:border-2 sm:shadow-comic sm:transition-none",
        (@open? && "translate-y-0") || "translate-y-full sm:hidden"
      ]}
    >
      <button
        type="button"
        data-drag-handle
        data-haptic
        class="flex w-full flex-none cursor-grab touch-none items-center justify-center gap-2 py-3 text-base-content/50 sm:hidden"
        title="Close filters"
      >
        <span class="h-1 w-10 rounded-full bg-base-content/25"></span>
        <.icon name="hero-chevron-down" class="size-4" />
      </button>

      <header class="hidden flex-none items-center justify-between border-b-2 border-line px-5 py-3 sm:flex">
        <h2 class="font-bangers text-[22px] tracking-[0.02em] text-primary">Filters</h2>
        <button
          type="button"
          phx-click={@on_toggle}
          aria-label="Close filters"
          class="grid size-8 cursor-pointer place-items-center text-base-content/50 hover:text-white"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </header>

      <form
        id={@id <> "-form"}
        phx-change={@on_change}
        class="min-h-0 flex-1 overflow-y-auto px-4 py-3 sm:px-5"
      >
        <section
          :for={{group, controls} <- @groups}
          class="mb-6 border-t border-line/70 pt-4 first:border-t-0 first:pt-1 last:mb-2"
        >
          <h3 class="mb-2.5 font-anton text-[13px] uppercase tracking-[0.08em] text-base-content/45">
            {group}
          </h3>
          <div class={group_layout(controls)}>
            <.control :for={control <- controls} control={control} sync={@sync} sheet_id={@id} />
          </div>
        </section>

        <div
          :if={@sync.residual != ""}
          class="mb-2 border border-dashed border-line px-3 py-2 font-barlow text-[13px] text-base-content/55"
        >
          Also filtering:
          <span class="font-ibm-mono text-[12.5px] text-base-content/80">{@sync.residual}</span>
          — edit in the search bar.
        </div>

        <footer class="sticky bottom-0 -mx-4 mt-2 flex flex-none items-center gap-3 border-t-2 border-line bg-base-100 px-4 py-3 pb-[max(env(safe-area-inset-bottom),0.75rem)] sm:-mx-5 sm:px-5">
          <.button type="button" phx-click={@on_clear}>Clear all</.button>
          {render_slot(@footer_extra)}
          <.button type="button" variant="primary" phx-click={@on_toggle} class="ml-auto">
            {(@count && "Show #{@count} results") || "Show results"}
          </.button>
        </footer>
      </form>
    </section>
    """
  end

  # -- controls ---------------------------------------------------------------

  attr :control, :map, required: true
  attr :sync, :map, required: true
  attr :sheet_id, :string, default: nil

  defp control(%{control: %{control: kind}} = assigns) when kind in [:chips, :checks] do
    assigns = assign(assigns, :selected, Map.get(assigns.sync.fields, assigns.control.name, []))

    ~H"""
    <div class="flex flex-wrap gap-1.5" role="group" aria-label={@control.label}>
      <input type="hidden" name={@control.name <> "[]"} value="" />
      <.chip
        :for={{value, label} <- @control.options}
        type="checkbox"
        name={@control.name <> "[]"}
        value={value}
        checked={value in @selected}
        dot_class={dot_class(@control.name, value)}
      >
        {label}
      </.chip>
    </div>
    """
  end

  defp control(%{control: %{control: :tristate}} = assigns) do
    assigns = assign(assigns, :selected, Map.get(assigns.sync.fields, assigns.control.name, ""))

    ~H"""
    <div class="flex items-center gap-1.5" role="radiogroup" aria-label={@control.label}>
      <span class={control_label_classes()}>{@control.label}</span>
      <.chip
        :for={{value, label} <- [{"", "Any"}, {"true", "Yes"}, {"false", "No"}]}
        type="radio"
        name={@control.name}
        value={value}
        checked={@selected == value}
      >
        {label}
      </.chip>
    </div>
    """
  end

  defp control(%{control: %{control: :toggle}} = assigns) do
    assigns = assign(assigns, :selected, Map.get(assigns.sync.fields, assigns.control.name, ""))

    ~H"""
    <div class="flex flex-wrap gap-1.5">
      <input type="hidden" name={@control.name} value="" />
      <.chip type="checkbox" name={@control.name} value="true" checked={@selected == "true"}>
        {@control.label}
      </.chip>
    </div>
    """
  end

  # Vocabulary fields render as a typeahead over a native <datalist>. A
  # half-typed value is harmless: FormSync only commits exact vocabulary
  # matches, so the query updates when a suggestion is picked (or the typed
  # text completes a value) and clears when the input empties.
  defp control(%{control: %{control: :select}} = assigns) do
    assigns =
      assigns
      |> assign(:selected, Map.get(assigns.sync.fields, assigns.control.name, ""))
      |> assign(:list_id, "#{assigns.sheet_id}-#{assigns.control.name}-list")

    ~H"""
    <label class="contents">
      <span class={control_label_classes()}>{@control.label}</span>
      <input
        type="text"
        name={@control.name}
        value={@selected}
        list={@list_id}
        placeholder="Any"
        autocomplete="off"
        spellcheck="false"
        phx-debounce="300"
        class="min-w-0 border-2 border-line bg-black px-2.5 py-1.5 font-barlow text-[14px] text-base-content outline-none placeholder:text-base-content/35 focus:border-primary"
      />
    </label>
    <datalist id={@list_id}>
      <option :for={{value, label} <- @control.options} value={value}>
        {if label != value, do: label}
      </option>
    </datalist>
    """
  end

  defp control(%{control: %{control: :number}} = assigns) do
    current = Map.get(assigns.sync.fields, assigns.control.name) || %{op: :eq, value: ""}
    assigns = assign(assigns, :current, current)

    ~H"""
    <div class="flex items-center gap-1.5">
      <span class={control_label_classes() <> " w-[86px] flex-none"}>{@control.label}</span>
      <select
        name={@control.name <> "_op"}
        aria-label={"#{@control.label} comparison"}
        class={select_classes()}
      >
        <option :for={op <- @control.ops} value={op} selected={op == @current.op}>
          {op_symbol(op)}
        </option>
      </select>
      <input
        type="text"
        inputmode="numeric"
        name={@control.name}
        value={@current.value}
        phx-debounce="300"
        aria-label={@control.label}
        class="w-14 border-2 border-line bg-black px-2 py-1.5 text-center font-barlow text-[14px] text-base-content outline-none focus:border-primary"
      />
    </div>
    """
  end

  @doc """
  A filter_pill-styled `<label>` wrapping an invisible checkbox/radio, so
  every option is a form input and each tap submits the sheet's form. Public
  for `footer_extra` slots (e.g. the deck browser's sort radios).
  """
  attr :type, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :checked, :boolean, required: true
  attr :dot_class, :string, default: nil
  slot :inner_block, required: true

  def chip(assigns) do
    ~H"""
    <label class={[
      "inline-flex min-h-[40px] cursor-pointer items-center gap-1.5 border-2 px-3.5 py-1.5 sm:min-h-0 sm:px-3",
      "font-barlow-condensed text-[13px] font-bold uppercase tracking-[0.07em] transition-colors sm:text-[12px]",
      (@checked && "border-transparent bg-primary text-primary-content") ||
        "border-neutral bg-base-300 text-base-content hover:text-white"
    ]}>
      <input type={@type} name={@name} value={@value} checked={@checked} class="sr-only" />
      <span
        :if={@dot_class}
        class={["size-2 rounded-[2px]", (@checked && "bg-primary-content") || @dot_class]}
      />
      {render_slot(@inner_block)}
    </label>
    """
  end

  # -- helpers ----------------------------------------------------------------

  defp visible_groups(registry, hide) do
    registry
    |> FormSchema.controls()
    |> Enum.map(fn {group, controls} ->
      {group, Enum.reject(controls, &(&1.name in hide))}
    end)
    |> Enum.reject(fn {_group, controls} -> controls == [] end)
  end

  # Number rows pack two to a row on wider screens; typeahead rows share a
  # label column so labels and inputs align vertically; everything else wraps.
  defp group_layout([%{control: :number} | _]),
    do: "grid grid-cols-1 gap-x-6 gap-y-1.5 sm:grid-cols-2"

  defp group_layout([%{control: :select} | _]),
    do: "grid grid-cols-[minmax(56px,auto)_1fr] items-center gap-x-3 gap-y-2"

  defp group_layout(_controls), do: "flex flex-wrap items-center gap-x-6 gap-y-2"

  defp dot_class("aspect", value), do: Map.get(@aspect_dots, value)
  defp dot_class(_field, _value), do: nil

  defp op_symbol(op), do: Map.fetch!(@op_symbols, op)

  defp control_label_classes,
    do:
      "font-barlow-condensed text-[13px] font-bold uppercase tracking-[0.07em] text-base-content/70"

  defp select_classes,
    do:
      "cursor-pointer border-2 border-line bg-black px-2 py-1.5 font-barlow text-[14px] text-base-content outline-none focus:border-primary"
end
