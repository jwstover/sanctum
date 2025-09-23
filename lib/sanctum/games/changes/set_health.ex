defmodule Sanctum.Games.Changes.SetHealth do
  @moduledoc false

  alias Ash.Changeset
  alias Sanctum.Heroes
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    case Map.get(changeset.context, :loaded_deck) do
      nil ->
        changeset

      deck ->
        current_form = Changeset.get_attribute(changeset, :form) || :alter_ego

        # We need to load the sides to get health values
        hero = Ash.get!(Heroes.Hero, deck.hero.id, load: [:hero_side, :alter_ego_side])

        {health, max_health} =
          case current_form do
            :hero -> {hero.hero_side.health, hero.hero_side.health}
            :alter_ego -> {hero.alter_ego_side.health, hero.alter_ego_side.health}
          end

        changeset
        |> Changeset.change_attribute(:health, health)
        |> Changeset.change_attribute(:max_health, max_health)
    end
  end
end
