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
      case Sanctum.Games.get_card_by_code!(value, load: [:primary_side]) do
        %Sanctum.Games.Card{
          primary_side: %{type: :hero}
        } ->
          :ok

        %Sanctum.Games.Card{primary_side: nil} ->
          {:error, field: :hero_code, message: "hero card must have a primary side"}

        %Sanctum.Games.Card{primary_side: %{type: type}} ->
          {:error, field: :hero_code, message: "hero must have type hero, got #{type}"}

        _ ->
          {:error, field: :hero_code, message: "hero must have type hero"}
      end
    else
      {:error, field: :hero_code, message: "must have a valid hero"}
    end
  end
end
