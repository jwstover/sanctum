defmodule Sanctum.Games.Changes.SetScenarioSet do
  @moduledoc """
  Copies `villain_set.code` into the scenario's `set` attribute so the
  `Card.set`-joined relationships (`villains`, `main_schemes`, `encounter_cards`)
  keep working.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :villain_set_id) do
      nil ->
        changeset

      id ->
        card_set = Ash.get!(Sanctum.Catalog.CardSet, id, authorize?: false)
        Ash.Changeset.force_change_attribute(changeset, :set, card_set.code)
    end
  end
end
