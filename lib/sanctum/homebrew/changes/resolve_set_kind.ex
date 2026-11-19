defmodule Sanctum.Homebrew.Changes.ResolveSetKind do
  @moduledoc """
  Resolves the `:kind` argument — free text from the set page's open kind
  combobox — to `set_kind_id`. The kind list only *suggests*, it never
  constrains:

    * blank → unclassified (`set_kind_id` nil);
    * text matching a usable kind's label (case-insensitively) or derived
      key → that existing kind, so picking a suggestion never duplicates a
      row (the project's own kind wins over an official one);
    * anything else → a newly minted project-scoped custom kind labelled
      with the text. No kind string is rejected: the key is derived from the
      label, with a generated fallback when the text has no usable
      characters.

  Runs in `before_action`, so only after the update policy has passed and
  inside the action's transaction — a failed update never leaves a freshly
  minted kind behind. Nothing happens when `:kind` is not passed.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Sanctum.Homebrew.SetKind

  @impl true
  def change(changeset, _opts, context) do
    case Changeset.fetch_argument(changeset, :kind) do
      {:ok, text} ->
        Changeset.before_action(changeset, &resolve(&1, text, context.actor))

      :error ->
        changeset
    end
  end

  defp resolve(changeset, text, actor) do
    label = text |> to_string() |> String.trim()

    if label == "" do
      Changeset.force_change_attribute(changeset, :set_kind_id, nil)
    else
      project_id = Changeset.get_attribute(changeset, :homebrew_project_id)
      key = kind_key(label)

      case find_kind(project_id, label, key, actor) || mint_kind(project_id, label, key, actor) do
        {:error, error} -> Changeset.add_error(changeset, error)
        kind -> Changeset.force_change_attribute(changeset, :set_kind_id, kind.id)
      end
    end
  end

  defp find_kind(project_id, label, key, actor) do
    kinds = Sanctum.Homebrew.list_project_set_kinds!(project_id, actor: actor)
    downcased = String.downcase(label)
    label_match? = &(String.downcase(&1.label) == downcased)

    Enum.find(kinds, &(&1.origin == :custom and label_match?.(&1))) ||
      Enum.find(kinds, label_match?) ||
      Enum.find(kinds, &(&1.origin == :custom and &1.key == key)) ||
      Enum.find(kinds, &(&1.key == key))
  end

  defp mint_kind(project_id, label, key, actor) do
    case Sanctum.Homebrew.create_set_kind(
           %{homebrew_project_id: project_id, key: key, label: label},
           actor: actor
         ) do
      {:ok, %SetKind{} = kind} -> kind
      {:error, error} -> {:error, error}
    end
  end

  # SetKind keys must match ~r/\A[a-z0-9][a-z0-9_-]*\z/. Labels like "!!!" or
  # "Ωmega" slugify to nothing; those get a generated key so the text is
  # still accepted as a label.
  defp kind_key(label) do
    slug =
      label
      |> String.normalize(:nfd)
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")
      |> String.slice(0, 60)
      |> String.trim("_")

    if slug == "", do: "kind_#{System.unique_integer([:positive])}", else: slug
  end
end
