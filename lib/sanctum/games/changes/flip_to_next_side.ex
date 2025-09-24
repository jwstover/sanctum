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

    current_active_side_id =
      Ash.Changeset.get_attribute(changeset, :active_side_id) ||
      Map.get(resource_data, :active_side_id) ||
      Ash.Changeset.get_attribute(changeset, :active_stage_side_id) ||
      Map.get(resource_data, :active_stage_side_id)

    if card_id do
      # Load the card with all its sides
      card = Sanctum.Games.get_card!(card_id, load: [:card_sides])

      # Get all sides sorted by side_identifier for consistent cycling
      available_sides =
        card.card_sides
        |> Enum.sort_by(& &1.side_identifier)

      next_side =
        case current_active_side_id do
          nil ->
            # No active side, use the primary side (first side)
            Enum.find(available_sides, &(&1.is_primary_side)) || List.first(available_sides)

          current_side_id ->
            # Find current side index and get next side
            current_index = Enum.find_index(available_sides, &(&1.id == current_side_id))

            if current_index do
              next_index = rem(current_index + 1, length(available_sides))
              Enum.at(available_sides, next_index)
            else
              # Fallback if active_side_id is invalid
              List.first(available_sides)
            end
        end

      changeset =
        if next_side do
          # Set the appropriate field based on what exists in the resource
          cond do
            Map.has_key?(resource_data, :active_side_id) ->
              Ash.Changeset.change_attribute(changeset, :active_side_id, next_side.id)

            Map.has_key?(resource_data, :active_stage_side_id) ->
              Ash.Changeset.change_attribute(changeset, :active_stage_side_id, next_side.id)

            true ->
              changeset
          end
        else
          changeset
        end

      # Optionally set face_up if requested
      if Keyword.get(opts, :set_face_up, false) do
        Ash.Changeset.change_attribute(changeset, :face_up, true)
      else
        changeset
      end
    else
      changeset
    end
  end
end