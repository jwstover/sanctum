defmodule Sanctum.Homebrew.Validations.SetInSameProject do
  @moduledoc """
  A `homebrew_set_id`, when set, must name a set whose `homebrew_project_id`
  equals the changeset's own. Resolved with `authorize?: false`, and meant to
  be attached with `before_action?: true` so it runs after the action's
  policy: a non-owner gets Forbidden, never this validation's Invalid, so the
  error class cannot probe which sets exist. Mirrors `ParentSetInSameProject`.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset
  alias Sanctum.Homebrew.Validations.ParentSetInSameProject

  @impl true
  def validate(changeset, _opts, _context) do
    set_id = Changeset.get_attribute(changeset, :homebrew_set_id)
    project_id = Changeset.get_attribute(changeset, :homebrew_project_id)

    cond do
      is_nil(set_id) -> :ok
      ParentSetInSameProject.same_project?(set_id, project_id) -> :ok
      true -> {:error, field: :homebrew_set_id, message: "must be a set in the same project"}
    end
  end
end
