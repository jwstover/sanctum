defmodule Sanctum.Games.Changes.SetHealth do
  @moduledoc false

  alias Ash.Changeset
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    case Map.get(changeset.context, :loaded_deck) |> IO.inspect(label: "================== loaded deck\n") do
      nil ->
        changeset
      
      deck ->
        current_form = Changeset.get_attribute(changeset, :form) || :alter_ego
        
        {health, max_health} = case current_form do
          :hero -> {deck.hero.health, deck.hero.health}
          :alter_ego -> {deck.alter_ego.health, deck.alter_ego.health}
        end
        
        changeset
        |> Changeset.change_attribute(:health, health)
        |> Changeset.change_attribute(:max_health, max_health)
    end
  end
end
