defmodule Sanctum.GameLog.Checks.LoggedGameOwnedByActor do
  @moduledoc """
  Policy check for LoggedGamePlayer creates: the logged game referenced by the
  changeset must belong to the actor. Filter checks can't see the target row
  on a create (it doesn't exist yet), so this resolves `logged_game_id` by hand.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "the changeset's logged game belongs to the actor"

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    with logged_game_id when not is_nil(logged_game_id) <-
           Ash.Changeset.get_attribute(changeset, :logged_game_id),
         {:ok, logged_game} <-
           Ash.get(Sanctum.GameLog.LoggedGame, logged_game_id, authorize?: false) do
      logged_game.user_id == actor.id
    else
      _missing_or_not_found -> false
    end
  end

  def match?(_actor, _context, _opts), do: false
end
