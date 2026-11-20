defmodule Sanctum.Homebrew.Changes.ActionOpenReports do
  @moduledoc """
  Part of `HomebrewSet :take_down`: once the set is down, its open
  `SetReport`s are marked `:actioned` by the same admin, in the same
  transaction. Reports are admin-only, so this runs as the action's actor.
  """

  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, set ->
      Sanctum.Homebrew.SetReport
      |> Ash.Query.filter(homebrew_set_id == ^set.id and status == :open)
      |> Ash.bulk_update!(
        :mark_actioned,
        %{},
        actor: context.actor,
        strategy: :stream,
        return_errors?: true
      )

      {:ok, set}
    end)
  end
end
