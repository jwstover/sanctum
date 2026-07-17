defmodule SanctumWeb.Components.QueryInput do
  @moduledoc """
  The advanced-search query input: a transparent-text `<input>` layered over a
  syntax-highlighting mirror, with a server-driven autocomplete listbox —
  wired up by the `QueryInput` JS hook.

  Must be rendered inside a `<form phx-change="...">`; the input participates
  in that form like a plain text input (same `name`, same debounce). The
  hosting LiveView provides suggestions by handling the hook's `"suggest"`
  event:

      def handle_event("suggest", %{"value" => v, "cursor" => c}, socket) do
        {:reply, Sanctum.Search.Suggest.suggest(v, c, MyRegistry), socket}
      end
  """

  use Phoenix.Component

  alias Sanctum.Search.Diagnostic

  attr :id, :string, required: true
  attr :value, :string, default: ""
  attr :name, :string, default: "query"
  attr :placeholder, :string, default: "Search…"

  attr :placeholder_short, :string,
    default: nil,
    doc: "shorter placeholder swapped in below the `sm` breakpoint (ResponsivePlaceholder hook)"

  attr :registry, :atom, required: true, doc: "Sanctum.Search.Registry module"
  attr :diagnostics, :list, default: []

  attr :help_path, :string,
    default: nil,
    doc: "when set, renders a “?” link to the search-syntax reference"

  def query_input(assigns) do
    assigns = assign(assigns, :field_names, field_names(assigns.registry))

    # The mirror div must keep identical padding to the input or the
    # highlight overlay drifts out of alignment — pr-9 on both reserves room
    # for the help link.
    ~H"""
    <div class="relative min-w-[260px] flex-1">
      <div id={@id} phx-hook="QueryInput" data-fields={Jason.encode!(@field_names)}>
        <span class="pointer-events-none absolute left-3.5 top-[21px] z-20 -translate-y-1/2 text-[17px] text-base-content/40">
          ⌕
        </span>
        <div class="relative border-[2.5px] border-line bg-black focus-within:border-primary">
          <div
            id={@id <> "-mirror"}
            phx-update="ignore"
            aria-hidden="true"
            class="qi-mirror pointer-events-none absolute inset-0 overflow-hidden whitespace-pre py-2.5 pl-[38px] pr-9 font-barlow text-base text-base-content sm:text-[15px]"
          >
          </div>
          <input
            type="text"
            id={@id <> "-input"}
            name={@name}
            value={@value}
            phx-debounce="200"
            autocomplete="off"
            spellcheck="false"
            autocapitalize="off"
            placeholder={@placeholder}
            phx-hook={@placeholder_short && "ResponsivePlaceholder"}
            data-placeholder-short={@placeholder_short}
            role="combobox"
            aria-expanded="false"
            aria-autocomplete="list"
            aria-controls={@id <> "-listbox"}
            class="relative z-10 w-full bg-transparent py-2.5 pl-[38px] pr-9 font-barlow text-base text-transparent caret-primary outline-none placeholder:text-base-content/35 sm:text-[15px]"
          />
          <.link
            :if={@help_path}
            navigate={@help_path}
            title="Search syntax help"
            aria-label="Search syntax help"
            class="absolute right-2.5 top-1/2 z-20 grid size-[18px] -translate-y-1/2 place-items-center rounded-full border border-base-content/30 font-barlow text-[11px] font-bold text-base-content/45 hover:border-primary hover:text-primary"
          >
            ?
          </.link>
        </div>
        <div
          id={@id <> "-listbox"}
          phx-update="ignore"
          role="listbox"
          class="qi-listbox absolute left-0 right-0 top-full z-30 mt-1.5 hidden max-h-72 overflow-y-auto border-2 border-neutral bg-base-200 shadow-comic"
        >
        </div>
      </div>
      <div
        :if={@diagnostics != []}
        class="pointer-events-none absolute left-0 top-full z-20 mt-1 border border-line bg-base-100/95 px-2 py-0.5 font-barlow text-[12.5px] leading-tight text-primary/90"
      >
        {format_diagnostic(hd(@diagnostics))}
      </div>
    </div>
    """
  end

  defp format_diagnostic(%Diagnostic{message: message}), do: "⚠ " <> message

  defp field_names(registry) do
    Enum.flat_map(registry.fields(), &[&1.name | &1.aliases])
  end
end
