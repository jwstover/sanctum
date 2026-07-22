defmodule Sanctum.Games.Changes.PairCustomCard do
  @moduledoc """
  Merges a donor single-sided custom card into the target as side "b".

  The donor's side is re-parented BEFORE the donor row is destroyed — the
  `card_sides.card_id` FK cascades on card delete. Internal writes run with
  `authorize?: false`: the action's policy already proved the actor owns the
  target's project, and the same-project validation below makes the donor the
  same creator's (projects have a single creator; the origin check constraint
  guarantees a same-project donor is custom).
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Sanctum.Games.CustomCode

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> Changeset.before_action(fn changeset ->
      donor_id = Changeset.get_argument(changeset, :donor_card_id)
      target = changeset.data

      with {:ok, donor} <- fetch_donor(donor_id, context.actor),
           :ok <- validate_pairable(target, donor) do
        Changeset.put_context(changeset, :pair_donor, donor)
      else
        {:error, field, message} ->
          Changeset.add_error(changeset, field: field, message: message)
      end
    end)
    |> Changeset.after_action(fn changeset, target ->
      donor = changeset.context.pair_donor
      [donor_side] = donor.card_sides

      # Re-parent FIRST (destroying the donor would cascade its sides away).
      donor_side
      |> Changeset.for_update(:update, %{
        card_id: target.id,
        side_identifier: "b",
        code: CustomCode.side_code(target.code, "b"),
        is_primary_side: false
      })
      |> Ash.update!(authorize?: false)

      # TODO(play-slice): a donor referenced by DeckCard/GameCard raises a raw
      # FK error here — turn that into a friendly validation when customs
      # become deckable/playable.
      Ash.destroy!(donor, action: :destroy_custom, authorize?: false)

      {:ok, target}
    end)
  end

  defp fetch_donor(donor_id, actor) do
    # Actor-scoped read: someone else's private custom is simply not found.
    case Ash.get(Sanctum.Games.Card, donor_id, actor: actor, load: :card_sides) do
      {:ok, donor} -> {:ok, donor}
      {:error, _not_found} -> {:error, :donor_card_id, "card not found"}
    end
  end

  defp validate_pairable(target, donor) do
    cond do
      donor.id == target.id ->
        {:error, :donor_card_id, "a card cannot be paired with itself"}

      donor.homebrew_project_id != target.homebrew_project_id ->
        # Covers cross-project, cross-user, and official donors in one check.
        {:error, :donor_card_id, "both cards must belong to the same project"}

      target.is_multi_sided ->
        {:error, :id, "this card already has two sides"}

      donor.is_multi_sided or length(donor.card_sides) != 1 ->
        {:error, :donor_card_id, "the other card must be single-sided"}

      true ->
        :ok
    end
  end
end
