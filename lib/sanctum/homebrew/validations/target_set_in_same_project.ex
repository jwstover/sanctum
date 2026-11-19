defmodule Sanctum.Homebrew.Validations.TargetSetInSameProject do
  @moduledoc """
  Moving a custom card (`Card :move_to_set`): the target `homebrew_set_id`
  must be a set in the same project as the card's current set. Cross-project
  moves are deliberately out of scope. Both sets are resolved with
  `authorize?: false`; the lookup only feeds the boolean. Attached
  `before_action?: true`, after the `ActorOwnsSet` policy has passed.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset
  alias Sanctum.Homebrew.HomebrewSet

  @impl true
  def validate(changeset, _opts, _context) do
    target_id = Changeset.get_attribute(changeset, :homebrew_set_id)
    current_id = changeset.data.homebrew_set_id

    with false <- is_nil(target_id),
         {:ok, target} <- Ash.get(HomebrewSet, target_id, authorize?: false),
         {:ok, current} <- Ash.get(HomebrewSet, current_id, authorize?: false),
         true <- target.homebrew_project_id == current.homebrew_project_id do
      :ok
    else
      # A nil target is `present(:homebrew_set_id)`'s error to report.
      true ->
        :ok

      _other_project_or_missing ->
        {:error, field: :homebrew_set_id, message: "must be a set in the same project"}
    end
  end
end
