defmodule Sanctum.Games.Changes.CopyScenario do
  @moduledoc """
  Copies the `source_id` scenario's villain set, notes and modular sets into a
  new scenario named `"Copy of <name>"`.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    source_id = Ash.Changeset.get_argument(changeset, :source_id)

    # Scenario reads are public, so any scenario may be copied.
    case Ash.get(Sanctum.Games.Scenario, source_id, load: [:modular_sets], authorize?: false) do
      {:ok, source} ->
        changeset
        |> Ash.Changeset.force_change_attributes(%{
          name: "Copy of #{source.name}",
          villain_set_id: source.villain_set_id,
          set: source.set,
          description_md: source.description_md
        })
        |> Ash.Changeset.manage_relationship(
          :modular_sets,
          Enum.map(source.modular_sets, & &1.id),
          type: :append_and_remove
        )

      {:error, _} ->
        Ash.Changeset.add_error(changeset, field: :source_id, message: "does not exist")
    end
  end
end
