defmodule Sanctum.Homebrew.Checks.ActorOwnsSetArgument do
  @moduledoc """
  Policy check for generic actions on a set given by its `set_id` argument:
  the set must belong to the actor. Generic actions have no record to put
  a filter check on, and a read-scoped walk is not enough — a published
  descendant is readable by anyone. The `authorize?: false` get only feeds
  the boolean.
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "the set_id argument's set belongs to the actor"

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(actor, %{subject: %Ash.ActionInput{} = input}, _opts) do
    with set_id when not is_nil(set_id) <- Ash.ActionInput.get_argument(input, :set_id),
         {:ok, set} <- Ash.get(Sanctum.Homebrew.HomebrewSet, set_id, authorize?: false) do
      set.creator_id == actor.id
    else
      _missing_or_not_found -> false
    end
  end

  def match?(_actor, _context, _opts), do: false
end
