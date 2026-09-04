defmodule Sanctum.Homebrew.Validations.ParentSetInSameProject do
  @moduledoc """
  A `parent_set_id`, when set, must point at a set in the same
  `homebrew_project` and must not be the set itself. Resolved with
  `authorize?: false` (the parent may be someone else's private set — the
  lookup only feeds the boolean and never leaks data). Attached at the action
  level to :create and :update with `where: [changing(:parent_set_id)]` and
  `before_action?: true`, so it only runs after the action's policy has
  passed: an actor who does not own the target project gets Forbidden, never
  this validation's Invalid, so the error class cannot be used to probe which
  sets live in projects they cannot read. Same-project implies same creator,
  which closes the cross-creator attachment hole.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset

  @impl true
  def validate(changeset, _opts, _context) do
    parent_id = Changeset.get_attribute(changeset, :parent_set_id)
    project_id = Changeset.get_attribute(changeset, :homebrew_project_id)

    cond do
      is_nil(parent_id) -> :ok
      parent_id == Changeset.get_data(changeset, :id) -> error("cannot be its own parent")
      same_project?(parent_id, project_id) -> :ok
      true -> error("must be a set in the same project")
    end
  end

  defp same_project?(parent_id, project_id) do
    case Ash.get(Sanctum.Homebrew.HomebrewSet, parent_id, authorize?: false) do
      {:ok, %{homebrew_project_id: ^project_id}} -> true
      _not_found_or_other_project -> false
    end
  end

  defp error(message), do: {:error, field: :parent_set_id, message: message}
end
