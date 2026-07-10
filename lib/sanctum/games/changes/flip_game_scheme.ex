defmodule Sanctum.Games.Changes.FlipGameScheme do
  @moduledoc """
  Flips a game scheme to its next available side and updates threat-related values
  based on the newly active side.

  This change module specifically handles GameScheme resources and:
  1. Flips to the next available side (using FlipToNextSide logic)
  2. Updates threat, escalation_threat, and max_threat from the new active side's values
  """

  use Ash.Resource.Change

  def change(changeset, opts, context) do
    # First, apply the standard flip logic
    changeset = Sanctum.Games.Changes.FlipToNextSide.change(changeset, opts, context)

    # Now update threat values based on the new active side
    update_threat_values_from_active_side(changeset)
  end

  defp update_threat_values_from_active_side(changeset) do
    # Get the new active_side_id that was set by FlipToNextSide
    new_active_side_id =
      Ash.Changeset.get_attribute(changeset, :active_side_id) ||
      Map.get(changeset.data, :active_side_id)

    if new_active_side_id do
      # Load the new active side to get its threat values
      active_side = Sanctum.Games.get_card_side!(new_active_side_id)

      changeset
      |> maybe_update_threat_from_side(active_side)
      |> maybe_update_escalation_threat_from_side(active_side)
      |> maybe_update_max_threat_from_side(active_side)
    else
      changeset
    end
  end

  defp maybe_update_threat_from_side(changeset, active_side) do
    if active_side.base_threat do
      Ash.Changeset.change_attribute(changeset, :threat, active_side.base_threat)
    else
      changeset
    end
  end

  defp maybe_update_escalation_threat_from_side(changeset, active_side) do
    if active_side.escalation_threat do
      Ash.Changeset.change_attribute(changeset, :escalation_threat, active_side.escalation_threat)
    else
      changeset
    end
  end

  defp maybe_update_max_threat_from_side(changeset, active_side) do
    if active_side.max_threat do
      Ash.Changeset.change_attribute(changeset, :max_threat, active_side.max_threat)
    else
      changeset
    end
  end
end