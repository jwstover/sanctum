defmodule Sanctum.Games.Changes.DefaultScenarioName do
  @moduledoc """
  Defaults a blank scenario name to `"<villain set name> Scenario"`.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    name = Ash.Changeset.get_attribute(changeset, :name)
    villain_set_id = Ash.Changeset.get_attribute(changeset, :villain_set_id)

    if (is_nil(name) or String.trim(name) == "") and not is_nil(villain_set_id) do
      case Ash.get(Sanctum.Catalog.CardSet, villain_set_id, authorize?: false) do
        {:ok, set} ->
          Ash.Changeset.force_change_attribute(
            changeset,
            :name,
            "#{set.name || set.code} Scenario"
          )

        # ValidateVillainSet reports the bad id.
        _ ->
          changeset
      end
    else
      changeset
    end
  end
end
