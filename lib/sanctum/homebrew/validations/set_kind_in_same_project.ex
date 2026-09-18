defmodule Sanctum.Homebrew.Validations.SetKindInSameProject do
  @moduledoc """
  A `set_kind_id`, when set, must point at an *official* kind or at a custom
  kind minted in the set's own `homebrew_project`. Custom kinds are
  project-scoped (their visibility follows the project), so without this a
  set could be classified by another creator's private kind — a row its own
  creator can never read, and one that creator could rename or delete out
  from under the set (`on_delete: :nilify`).

  Resolved with `authorize?: false` (the kind may be someone else's private
  row — the lookup only feeds the boolean and never leaks data). Attached at
  the action level to :create and :update with
  `where: [changing(:set_kind_id)]` and `before_action?: true`, so it only
  runs after the action's policy has passed: a Forbidden actor never reaches
  the lookup, which keeps success/failure from doubling as an existence
  oracle for other projects' kind ids.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset

  @impl true
  def validate(changeset, _opts, _context) do
    kind_id = Changeset.get_attribute(changeset, :set_kind_id)
    project_id = Changeset.get_attribute(changeset, :homebrew_project_id)

    cond do
      is_nil(kind_id) -> :ok
      usable_kind?(kind_id, project_id) -> :ok
      true -> error("must be an official kind or a kind defined in the same project")
    end
  end

  defp usable_kind?(kind_id, project_id) do
    case Ash.get(Sanctum.Homebrew.SetKind, kind_id, authorize?: false) do
      {:ok, %{origin: :official}} -> true
      {:ok, %{homebrew_project_id: ^project_id}} -> true
      _not_found_or_other_project -> false
    end
  end

  defp error(message), do: {:error, field: :set_kind_id, message: message}
end
