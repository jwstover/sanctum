defmodule Sanctum.Decks.Validations.ValidateHero do
  @moduledoc false

  use Ash.Resource.Validation

  @impl true
  def init(opts) do
    {:ok, opts}
  end

  @impl true
  def supports(_opts), do: [Ash.Changeset]

  @impl true
  def validate(subject, _opts, _context) do
    value = Ash.Changeset.get_attribute(subject, :hero_id)

    if value do
      case Ash.get!(Sanctum.Heroes.Hero, value, load: [card: [:card_sides]]) do
        %Sanctum.Heroes.Hero{card: card} when not is_nil(card) ->
          # Check that the card has both hero and alter ego sides
          sides = card.card_sides || []
          hero_side = Enum.find(sides, &(&1.type == :hero))
          alter_ego_side = Enum.find(sides, &(&1.type == :alter_ego))

          if hero_side && alter_ego_side do
            :ok
          else
            {:error,
             field: :hero_id, message: "hero card must have both hero and alter ego sides"}
          end

        %Sanctum.Heroes.Hero{card: nil} ->
          {:error, field: :hero_id, message: "hero must have a valid card"}

        _ ->
          {:error, field: :hero_id, message: "must be a valid hero"}
      end
    else
      {:error, field: :hero_id, message: "must have a valid hero"}
    end
  end
end
