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
    case Ash.Changeset.get_attribute(subject, :hero_id) do
      nil ->
        {:error, field: :hero_id, message: "must have a valid hero"}

      value ->
        Sanctum.Heroes.Hero
        |> Ash.get!(value, load: [card: [:card_sides]])
        |> validate_hero_card()
    end
  end

  defp validate_hero_card(%Sanctum.Heroes.Hero{card: card}) when not is_nil(card) do
    sides = card.card_sides || []
    hero_side = Enum.find(sides, &(&1.type == :hero))
    alter_ego_side = Enum.find(sides, &(&1.type == :alter_ego))

    if hero_side && alter_ego_side do
      :ok
    else
      {:error, field: :hero_id, message: "hero card must have both hero and alter ego sides"}
    end
  end

  defp validate_hero_card(%Sanctum.Heroes.Hero{card: nil}) do
    {:error, field: :hero_id, message: "hero must have a valid card"}
  end

  defp validate_hero_card(_), do: {:error, field: :hero_id, message: "must be a valid hero"}
end
