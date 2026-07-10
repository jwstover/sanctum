defmodule Sanctum.Games.Changes.AssignOrder do
  @moduledoc """
  Assigns the next available `order` for a card within its zone.

  - Uses gapped integers (increments of 10).
  - Skips assignment if `order` is already provided in the changeset.
  - Scopes by `game_encounter_deck_id` + `zone` when present, otherwise by
    `game_player_id` + `zone`.

  Concurrency safety: the max(order) read and the subsequent write must not
  interleave with a competing move into the same zone, or two moves could read
  the same max and produce colliding orders. To prevent this the work runs
  inside the action's transaction (see `transaction? true` on the `:move`
  action) as a `before_action` hook, and takes a transaction-scoped Postgres
  advisory lock keyed on the (scope, zone) pair before reading the max. The
  lock is released automatically when the transaction commits or rolls back.
  """

  use Ash.Resource.Change
  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    # Only assign if no `order` was explicitly set
    if Ash.Changeset.changing_attribute?(changeset, :order) do
      changeset
    else
      Ash.Changeset.before_action(changeset, &assign_order/1)
    end
  end

  defp assign_order(changeset) do
    zone = Ash.Changeset.get_attribute(changeset, :zone)
    game_player_id = Ash.Changeset.get_attribute(changeset, :game_player_id)
    game_encounter_deck_id = Ash.Changeset.get_attribute(changeset, :game_encounter_deck_id)

    scope_id = game_encounter_deck_id || game_player_id

    # Take a transaction-scoped advisory lock so concurrent moves into the same
    # (scope, zone) serialize around the max(order) read/write.
    lock_key = :erlang.phash2({scope_id, zone})
    Sanctum.Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_key])

    query =
      if game_encounter_deck_id do
        Sanctum.Games.GameCard
        |> Ash.Query.filter(game_encounter_deck_id == ^game_encounter_deck_id and zone == ^zone)
      else
        Sanctum.Games.GameCard
        |> Ash.Query.filter(game_player_id == ^game_player_id and zone == ^zone)
      end

    max_order = Ash.max!(query, :order, authorize?: false) || 0

    Ash.Changeset.force_change_attribute(changeset, :order, max_order + 10)
  end
end
