defmodule Sanctum.Games.Changes.CreateGamePlayer do
  @moduledoc false

  alias Sanctum.Accounts.User

  use Ash.Resource.Change

  def change(changeset, _opts, %{actor: %User{} = user}) do
    Ash.Changeset.manage_relationship(changeset, :game_players, [%{user_id: user.id}],
      type: :create,
      use_identities: [:unique_game_id_user_id]
    )
  end

  def change(changeset, _opts, _context), do: changeset
end
