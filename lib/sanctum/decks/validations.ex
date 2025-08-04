defmodule Sanctum.Decks.Validations do
  @moduledoc false

  use Ash.Resource.Validation

  def hero_must_be_hero_type(changeset, _opts, _context) do
    Ash.Changeset.get_attribute(changeset, :hero_code)
    |> validate_card_type()
  end

  @spec validate_card_type(String.t() | nil) ::
          :ok | {:error, field: :hero_code, message: String.t()}
  def validate_card_type(nil), do: {:error, field: :hero_code, message: "must have a valid hero"}

  def validate_card_type(code) do
    case Ash.get(Sanctum.Games.Card, code, load: [:type_code]) do
      {:ok, card} ->
        if card.type_code == "hero" do
          :ok
        else
          {:error, field: :hero_code, message: "must be a hero card"}
        end

      {:error, _} ->
        {:error, field: :hero_code, message: "card not found"}
    end
  end
end
