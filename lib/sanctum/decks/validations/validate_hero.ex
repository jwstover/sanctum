defmodule Sanctum.Decks.Validations.ValidateHero do
  @moduledoc false

  use Ash.Resource.Validation

  require Ash.Query

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

  defp validate_hero_card(%Sanctum.Heroes.Hero{card: card} = hero) when not is_nil(card) do
    sides = card.card_sides || []

    cond do
      not Enum.any?(sides, &(&1.type == :hero)) ->
        {:error, field: :hero_id, message: "hero card must have a hero side"}

      # The alter-ego form must exist, but not necessarily on the identity card
      # itself: split-identity heroes like SP//dr spread the hero and alter-ego
      # forms across two cards in the same set (SP//dr Suit + Peni Parker), so
      # we look for the alter-ego side anywhere in the identity card's set. (Use
      # the card's set, not the Hero's — they match in real data, but a Hero can
      # be pointed at a card from another set.)
      not set_has_alter_ego?(hero.card.set) ->
        {:error, field: :hero_id, message: "hero must have an alter ego side"}

      true ->
        :ok
    end
  end

  defp validate_hero_card(%Sanctum.Heroes.Hero{card: nil}) do
    {:error, field: :hero_id, message: "hero must have a valid card"}
  end

  defp validate_hero_card(_), do: {:error, field: :hero_id, message: "must be a valid hero"}

  # Does any card in this hero's set carry an alter-ego side? True for standard
  # heroes (same card) and split-identity heroes (a sibling card) alike.
  defp set_has_alter_ego?(set) do
    Sanctum.Games.Card
    |> Ash.Query.filter(set == ^set and exists(card_sides, type == :alter_ego))
    |> Ash.Query.limit(1)
    |> Ash.read!(authorize?: false)
    |> Enum.any?()
  end
end
