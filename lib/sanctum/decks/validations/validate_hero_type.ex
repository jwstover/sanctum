defmodule Sanctum.Decks.Validations.ValidateHeroType do
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
    value = Ash.Changeset.get_attribute(subject, :hero_code)

    if value do
      case Sanctum.Games.get_card_by_code!(value) do
        %Sanctum.Games.Card{type: :hero} -> :ok
        _ -> {:error, field: :hero_code, message: "hero must have type_code hero"}
      end
    else
      {:error, field: :hero_code, message: "must have a valid hero"}
    end
  end
end
