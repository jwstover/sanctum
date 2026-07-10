defmodule Sanctum.Games.Changes.FlipToNextSide do
  @moduledoc """
  Flips a resource to its next available side by cycling through card sides.

  This change module works with any resource that has:
  - `card_id` field pointing to a Card resource
  - `active_side_id` field pointing to a CardSide resource

  Options:
  - `:set_face_up` - If true, also sets face_up: true (default: false)
  """

  use Ash.Resource.Change

  def change(changeset, opts, _context) do
    resource_data = changeset.data

    # Handle different field name patterns for different resources
    card_id =
      Ash.Changeset.get_attribute(changeset, :card_id) ||
        Map.get(resource_data, :card_id) ||
        Ash.Changeset.get_attribute(changeset, :active_stage_card_id) ||
        Map.get(resource_data, :active_stage_card_id)

    if card_id do
      changeset
      |> flip_active_side(card_id, resource_data)
      |> maybe_set_face_up(opts)
    else
      changeset
    end
  end

  defp flip_active_side(changeset, card_id, resource_data) do
    current_active_side_id =
      Ash.Changeset.get_attribute(changeset, :active_side_id) ||
        Map.get(resource_data, :active_side_id) ||
        Ash.Changeset.get_attribute(changeset, :active_stage_side_id) ||
        Map.get(resource_data, :active_stage_side_id)

    # Load the card with all its sides, sorted by side_identifier for consistent cycling
    available_sides =
      card_id
      |> Sanctum.Games.get_card!(load: [:card_sides])
      |> Map.get(:card_sides)
      |> Enum.sort_by(& &1.side_identifier)

    case next_side(available_sides, current_active_side_id) do
      nil -> changeset
      next_side -> put_active_side(changeset, resource_data, next_side.id)
    end
  end

  # No active side yet: use the primary side (or the first available).
  defp next_side(available_sides, nil) do
    Enum.find(available_sides, & &1.is_primary_side) || List.first(available_sides)
  end

  # Cycle to the side after the current one, wrapping around.
  defp next_side(available_sides, current_side_id) do
    case Enum.find_index(available_sides, &(&1.id == current_side_id)) do
      nil ->
        List.first(available_sides)

      current_index ->
        next_index = rem(current_index + 1, length(available_sides))
        Enum.at(available_sides, next_index)
    end
  end

  # Set whichever active-side field this resource actually has.
  defp put_active_side(changeset, resource_data, next_side_id) do
    cond do
      Map.has_key?(resource_data, :active_side_id) ->
        Ash.Changeset.change_attribute(changeset, :active_side_id, next_side_id)

      Map.has_key?(resource_data, :active_stage_side_id) ->
        Ash.Changeset.change_attribute(changeset, :active_stage_side_id, next_side_id)

      true ->
        changeset
    end
  end

  defp maybe_set_face_up(changeset, opts) do
    if Keyword.get(opts, :set_face_up, false) do
      Ash.Changeset.change_attribute(changeset, :face_up, true)
    else
      changeset
    end
  end
end
