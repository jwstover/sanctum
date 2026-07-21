defmodule Sanctum.Search.FormSchema do
  @moduledoc """
  Derives the structured filter controls (the "Filters" sheet) from a search
  field registry, so the form UI and the query language stay one-to-one:
  every control corresponds to a registry field and round-trips through that
  field's query syntax via `Sanctum.Search.FormSync`.

  A field renders in the sheet iff its `form` metadata assigns a `:group`;
  everything else stays query-syntax-only. The control type derives from
  `Field.kind` unless `form.control` overrides it:

    * `:enum` → `:chips` — tappable multi-select (`aspect:justice|leadership`)
    * `:flag` → `:checks` — one checkbox per flag, one clause each (`is:unique`)
    * `:boolean` → `:tristate` — Any / Yes / No (`unique:true`)
    * `:text` with `values_fun` → `:select` — vocabulary dropdown (`hero:"…"`)
    * `:integer` / `:stat` → `:number` — operator + value (`cost<=2`)
    * plain `:text` → no control
  """

  alias Sanctum.Search.Field

  @type control_kind :: :chips | :checks | :tristate | :toggle | :select | :number

  @type control :: %{
          field: Field.t(),
          name: String.t(),
          label: String.t(),
          control: control_kind(),
          group: String.t(),
          order: integer(),
          ops: [Field.op()],
          options: [{String.t(), String.t()}]
        }

  @doc """
  Ordered `{group, controls}` list for a registry's filter sheet. Groups are
  ordered by their first member's `form.order`; members by their own.
  Option lists resolve `values_fun` lazily at call time.
  """
  @spec controls(module()) :: [{String.t(), [control()]}]
  def controls(registry) do
    registry.fields()
    |> Enum.filter(&control_for/1)
    |> Enum.map(&to_control/1)
    |> Enum.group_by(& &1.group)
    |> Enum.map(fn {group, controls} -> {group, Enum.sort_by(controls, & &1.order)} end)
    |> Enum.sort_by(fn {_group, [first | _]} -> first.order end)
  end

  @doc """
  The sheet control for a field, or nil when the field is query-syntax-only.
  Also the gate `Sanctum.Search.FormSync` uses to decide which clauses the
  form manages.
  """
  @spec control_for(Field.t() | nil) :: control_kind() | nil
  def control_for(%Field{form: %{group: _} = form} = field),
    do: form[:control] || derived(field)

  def control_for(_field), do: nil

  defp derived(%Field{kind: :enum}), do: :chips
  defp derived(%Field{kind: :flag}), do: :checks
  defp derived(%Field{kind: :boolean}), do: :tristate
  defp derived(%Field{kind: :text, values_fun: fun}) when is_function(fun, 0), do: :select
  defp derived(%Field{kind: kind}) when kind in [:integer, :stat], do: :number
  defp derived(_field), do: nil

  @doc ~s(Human label for a field/value slug: "player_side_scheme" → "Player Side Scheme".)
  @spec humanize(String.t()) :: String.t()
  def humanize(value) do
    value
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp to_control(%Field{form: form} = field) do
    control = control_for(field)

    %{
      field: field,
      name: field.name,
      label: form[:label] || humanize(field.name),
      control: control,
      group: form.group,
      order: form[:order] || 0,
      ops: field.ops,
      options: options(field, control)
    }
  end

  # Numeric and boolean-ish controls render fixed inputs, not option lists.
  defp options(_field, control) when control in [:number, :tristate, :toggle], do: []

  defp options(%Field{form: form} = field, control) do
    labeler = form[:option_labels] || default_labeler(control)

    (field.values ++ dynamic_values(field))
    |> Enum.uniq()
    |> Enum.map(&{&1, labeler.(&1)})
  end

  defp dynamic_values(%Field{values_fun: fun}) when is_function(fun, 0), do: fun.()
  defp dynamic_values(_field), do: []

  # Vocabulary values (hero names, traits) are already display-cased; enum
  # and flag slugs need humanizing.
  defp default_labeler(:select), do: &Function.identity/1
  defp default_labeler(_control), do: &humanize/1
end
