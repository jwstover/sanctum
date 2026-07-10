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
      case Sanctum.Games.get_card!(value, load: [:primary_side]) do
        %Sanctum.Games.Card{
          primary_side: %{type: :villain}
        } ->
          :ok

        %Sanctum.Games.Card{primary_side: nil} ->
          {:error, field: :villain_id, message: "villain card must have a primary side"}

        %Sanctum.Games.Card{primary_side: %{type: type}} ->
          {:error, field: :villain_id, message: "villain must have type villain, got #{type}"}

        _ ->
          {:error, field: :villain_id, message: "villain must have type villain"}
      end
    else
      {:error, field: :villain_id, message: "must have a valid villain"}
    end
  end
end
