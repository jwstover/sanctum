defmodule Sanctum.Games.Changes.FlipSchemeCard do
  @moduledoc """
  Flips a main scheme `GameCard` to its next available side and resets its
  threat based on the newly active side.

  1. Flips to the next available side (using `FlipToNextSide` logic).
  2. Resets `threat` from the new active side's `base_threat`.

  `max_threat` and `escalation_threat` are not stored on the `GameCard`; they are
  read from the active side (`CardSide`) wherever they are needed.
  """

  use Ash.Resource.Change

  def change(changeset, opts, context) do
    changeset
    |> Sanctum.Games.Changes.FlipToNextSide.change(opts, context)
    |> reset_threat_from_active_side()
  end

  defp reset_threat_from_active_side(changeset) do
    new_active_side_id =
      Ash.Changeset.get_attribute(changeset, :active_side_id) ||
        Map.get(changeset.data, :active_side_id)

    if is_binary(new_active_side_id) do
      active_side = Sanctum.Games.get_card_side!(new_active_side_id)

      case active_side.base_threat do
        %{value: threat} when not is_nil(threat) ->
          Ash.Changeset.change_attribute(changeset, :threat, threat)

        _ ->
          changeset
      end
    else
      changeset
    end
  end
end
