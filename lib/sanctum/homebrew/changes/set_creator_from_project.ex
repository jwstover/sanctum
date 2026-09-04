defmodule Sanctum.Homebrew.Changes.SetCreatorFromProject do
  @moduledoc """
  Stamps `creator_id` on a new `HomebrewSet` from its project's `creator_id`.

  `creator_id` is denormalized and never user input: the attribute is not
  writable/accepted by any action (a supplied value is rejected as
  NoSuchInput), and this hook force-sets it in `before_action`, overriding
  anything a caller managed to put on the changeset. Runs after policies
  (ActorOwnsProject has already proven the actor owns the project, or the
  admin bypass fired); the `authorize?: false` get never returns data to the
  caller — it only feeds the stamp. Ash only requires *accepted* required
  attributes at changeset-build time and re-checks the rest after
  before_action hooks, which is why an `allow_nil? false` FK can be filled in
  here (same pattern as `Sanctum.Games.Changes.CreateCustomAltArt`).
  """

  use Ash.Resource.Change

  alias Ash.Changeset

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.before_action(changeset, fn changeset ->
      case fetch_project(Changeset.get_attribute(changeset, :homebrew_project_id)) do
        {:ok, project} ->
          Changeset.force_change_attribute(changeset, :creator_id, project.creator_id)

        :error ->
          Changeset.add_error(changeset,
            field: :homebrew_project_id,
            message: "project not found"
          )
      end
    end)
  end

  defp fetch_project(nil), do: :error

  defp fetch_project(project_id) do
    case Ash.get(Sanctum.Homebrew.HomebrewProject, project_id, authorize?: false) do
      {:ok, project} -> {:ok, project}
      {:error, _not_found} -> :error
    end
  end
end
