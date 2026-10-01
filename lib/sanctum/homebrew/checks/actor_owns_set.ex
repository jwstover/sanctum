defmodule Sanctum.Homebrew.Checks.ActorOwnsSet do
  @moduledoc """
  Policy check for custom-card creates: the homebrew set referenced by
  the changeset must belong to the actor. Filter checks can't see the target
  set on a create (the row doesn't exist yet), so this resolves
  `homebrew_set_id` by hand. The `authorize?: false` get never returns
  data to the caller — it only feeds the boolean.
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "the changeset's homebrew set belongs to the actor"

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    with set_id when not is_nil(set_id) <-
           Ash.Changeset.get_attribute(changeset, :homebrew_set_id),
         {:ok, set} <-
           Ash.get(Sanctum.Homebrew.HomebrewSet, set_id, authorize?: false) do
      set.creator_id == actor.id
    else
      _missing_or_not_found -> false
    end
  end

  def match?(_actor, _context, _opts), do: false
end
