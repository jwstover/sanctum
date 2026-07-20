defmodule Sanctum.Decks.Checks.DeckOwnedByActor do
  @moduledoc """
  Policy check for DeckCard creates: the deck referenced by the changeset
  must belong to the actor. Filter checks can't see the target deck on a
  create (the row doesn't exist yet), so this resolves `deck_id` by hand.
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "the changeset's deck belongs to the actor"

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    with deck_id when not is_nil(deck_id) <-
           Ash.Changeset.get_attribute(changeset, :deck_id),
         {:ok, deck} <- Ash.get(Sanctum.Decks.Deck, deck_id, authorize?: false) do
      deck.owner_id == actor.id
    else
      _missing_or_not_found -> false
    end
  end

  def match?(_actor, _context, _opts), do: false
end
