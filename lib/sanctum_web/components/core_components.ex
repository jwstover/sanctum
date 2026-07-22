defmodule SanctumWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: SanctumWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global,
    include: ~w(href navigate patch replace method download name value disabled type target rel)

  attr :class, :string, default: ""
  attr :variant, :string, values: ~w(primary ghost icon)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    base =
      "inline-flex min-h-[44px] items-center justify-center gap-2 cursor-pointer font-barlow-condensed font-extrabold uppercase tracking-[0.08em] text-sm transition-all active:translate-x-px active:translate-y-px disabled:opacity-40 disabled:pointer-events-none sm:min-h-0"

    variants = %{
      "primary" =>
        "px-4 py-2.5 bg-primary text-primary-content border-2 border-transparent shadow-comic-sm hover:shadow-comic",
      "ghost" =>
        "px-4 py-2.5 bg-base-300 text-base-content border-2 border-neutral shadow-comic-sm hover:text-white",
      "icon" =>
        "size-11 rounded-full bg-base-300 text-base-content border-2 border-neutral hover:text-white sm:size-10",
      nil =>
        "px-4 py-2.5 bg-base-300 text-base-content border-2 border-neutral shadow-comic-sm hover:text-white"
    }

    assigns =
      assign(assigns, :class, [
        base,
        Map.fetch!(variants, assigns[:variant]),
        Map.fetch!(assigns, :class)
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders a "← Back" button that returns the user to wherever they came from
  (`history.back()`), so list pages restore their query/scroll state via the
  ScrollRestore hook instead of landing at the top. When there's nothing
  in-app to go back to (direct link, new tab), it navigates to `fallback`.

  ## Examples

      <.back_button fallback={~p"/cards"} />
  """
  attr :fallback, :string, required: true

  def back_button(assigns) do
    ~H"""
    <.button type="button" id="back-nav" phx-hook=".BackNav" data-fallback={@fallback}>
      <.icon name="hero-arrow-left" /> Back
    </.button>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".BackNav">
      // The Navigation API's canGoBack only counts same-origin entries, so it
      // correctly rejects a new-tab page or an external referrer;
      // history.length (the Firefox/Safari fallback) can't tell those apart
      // and may step out of the app.
      export default {
        mounted() {
          this.onClick = () => {
            const canGoBack =
              "navigation" in window ? window.navigation.canGoBack : window.history.length > 1

            if (canGoBack) {
              window.history.back()
            } else {
              window.location.assign(this.el.dataset.fallback || "/")
            }
          }
          this.el.addEventListener("click", this.onClick)
        },

        destroyed() {
          this.el.removeEventListener("click", this.onClick)
        },
      }
    </script>
    """
  end

  @doc """
  Renders a comic-dossier filter pill (aspect / type filters, sort toggles).

  ## Examples

      <.filter_pill active={@aspect == :hero} dot_class="bg-aspect-hero" phx-click="filter">
        Hero
      </.filter_pill>
  """
  attr :active, :boolean, default: false

  attr :dot_class, :string,
    default: nil,
    doc: "optional Tailwind bg-* class for a leading square swatch (e.g. bg-aspect-hero)"

  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(href navigate patch phx-click phx-value-key value name type)
  slot :inner_block, required: true

  def filter_pill(assigns) do
    ~H"""
    <button
      class={[
        "inline-flex min-h-[44px] items-center gap-1.5 cursor-pointer border-2 px-3.5 py-1.5 sm:min-h-0 sm:px-3",
        "font-barlow-condensed text-sm font-bold uppercase tracking-[0.07em] transition-colors sm:text-xs",
        (@active && "border-transparent bg-primary text-primary-content") ||
          "border-neutral bg-base-300 text-base-content hover:text-white",
        @class
      ]}
      {@rest}
    >
      <span
        :if={@dot_class}
        class={["size-2 rounded-[2px]", (@active && "bg-primary-content") || @dot_class]}
      />
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders a comic-dossier panel: hard black border + offset drop-shadow on a
  dark surface. The signature "printed cardstock" container.
  """
  attr :class, :string, default: ""
  attr :rest, :global
  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <div class={["border-2 border-neutral bg-base-200 shadow-comic", @class]} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a deck's uniqueness score as a gold meter (percentile + bar + label).

  Renders nothing when `percentile` is nil (an unscored deck). `size="lg"` is
  the deck-detail variant; the default `"sm"` is the compact list-row variant.

      <.uniqueness_meter percentile={87} />
      <.uniqueness_meter percentile={92} size="lg" />
  """
  attr :percentile, :integer, default: nil
  attr :size, :string, default: "sm", values: ~w(sm lg)
  attr :class, :string, default: nil

  def uniqueness_meter(assigns) do
    ~H"""
    <div :if={@percentile} class={@class}>
      <div class="flex items-baseline gap-1">
        <span class={[
          "font-anton leading-none text-primary",
          (@size == "lg" && "text-3xl") || "text-2xl"
        ]}>
          {@percentile}
        </span>
        <span class="font-barlow-condensed text-xs font-bold uppercase tracking-[0.08em] text-base-content/40">
          /100
        </span>
      </div>
      <div class={[
        "mt-1 border border-neutral bg-black",
        (@size == "lg" && "h-[6px] w-[150px]") || "h-[5px] w-full"
      ]}>
        <div class="h-full bg-primary" style={"width:#{@percentile}%"}></div>
      </div>
      <div class="mt-1 font-barlow-condensed text-xs font-bold uppercase tracking-[0.1em] text-base-content/50">
        Uniqueness
      </div>
    </div>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset">
      <label>
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="flex flex-col gap-1.5">
      <span
        :if={@label}
        class="font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/60"
      >
        {@label}
      </span>
      <select
        id={@id}
        name={@name}
        class={[
          @class ||
            "w-full bg-black border-[2.5px] border-[#2a2a30] text-base-content font-barlow-condensed font-bold uppercase tracking-[0.04em] px-3 py-2.5 outline-none focus:border-primary",
          @errors != [] && (@error_class || "border-error")
        ]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="flex flex-col gap-1.5">
      <span
        :if={@label}
        class="font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/60"
      >
        {@label}
      </span>
      <textarea
        id={@id}
        name={@name}
        class={[
          @class ||
            "w-full bg-black border-[2.5px] border-[#2a2a30] text-base-content font-barlow px-3.5 py-2.5 outline-none resize-y focus:border-primary",
          @errors != [] && (@error_class || "border-error")
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="flex flex-col gap-1.5">
      <span
        :if={@label}
        class="font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/60"
      >
        {@label}
      </span>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          @class ||
            "w-full bg-black border-[2.5px] border-[#2a2a30] text-base-content font-barlow px-3.5 py-2.5 outline-none focus:border-primary placeholder:text-base-content/40",
          @errors != [] && (@error_class || "border-error")
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :actions

  def header(assigns) do
    ~H"""
    <header class="mb-6 border-b-[3px] border-neutral pb-4">
      <div class={[
        @actions != [] && "flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between sm:gap-6"
      ]}>
        <div class="min-w-0">
          <h1 class="font-anton text-3xl uppercase leading-[0.9] tracking-[0.005em] md:text-4xl">
            {render_slot(@inner_block)}
          </h1>
        </div>
        <div :if={@actions != []} class="flex flex-none items-center justify-end gap-2.5">
          {render_slot(@actions)}
        </div>
      </div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  attr :rest, :global, include: ~w(phx-viewport-top phx-viewport-bottom)

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"} {@rest}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(SanctumWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(SanctumWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
