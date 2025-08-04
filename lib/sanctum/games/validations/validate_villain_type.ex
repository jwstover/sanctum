defmodule Sanctum.Games.Validations.ValidateVillainType do
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
    value = Ash.Changeset.get_attribute(subject, :villain_id)

    if value do
      case Sanctum.Games.get_card!(value) do
        %Sanctum.Games.Card{type: :villain} -> :ok
        _ -> {:error, field: :villain_id, message: "villain must have type_code villain"}
      end
    else
      {:error, field: :villain_id, message: "must have a valid villain"}
    end
  end
end
