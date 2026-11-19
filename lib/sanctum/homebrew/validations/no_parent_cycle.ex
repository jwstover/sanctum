defmodule Sanctum.Homebrew.Validations.NoParentCycle do
  @moduledoc """
  A set can't be nested under itself or under one of its own descendants —
  depth is unbounded, so that would close a cycle no tree walk could leave.

  Runs `before_action?: true` on `HomebrewSet :set_parent`, i.e. after the
  update policy and inside the action's transaction. It first locks the
  set's `HomebrewProject` row `FOR UPDATE`: cycles can only form within one
  project, so that row is a per-project mutex that serializes concurrent
  re-parents (a lone row lock cannot deadlock against itself the way an
  unordered lock over many set rows could). The subtree is read *after* the
  lock, so it sees any re-parent that committed while this one waited.
  System reads (`authorize?: false`): the result only feeds the boolean.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset
  alias Sanctum.Homebrew.HomebrewProject
  alias Sanctum.Homebrew.HomebrewSet

  require Ash.Query

  @impl true
  def validate(changeset, _opts, _context) do
    parent_id = Changeset.get_attribute(changeset, :parent_set_id)
    set = changeset.data

    cond do
      is_nil(parent_id) ->
        :ok

      parent_id == set.id ->
        {:error, field: :parent_set_id, message: "cannot be its own parent"}

      true ->
        lock_project!(set.homebrew_project_id)

        if parent_id in subtree_ids(set.id) do
          {:error,
           field: :parent_set_id, message: "can't be nested under one of its own child sets"}
        else
          :ok
        end
    end
  end

  defp lock_project!(project_id) do
    HomebrewProject
    |> Ash.Query.filter(id == ^project_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read!(authorize?: false)
  end

  defp subtree_ids(set_id) do
    HomebrewSet
    |> Ash.Query.for_read(:subtree, %{set_id: set_id}, authorize?: false)
    |> Ash.Query.select([:id])
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.id)
  end
end
