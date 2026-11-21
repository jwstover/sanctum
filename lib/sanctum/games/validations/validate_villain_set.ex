defmodule Sanctum.Games.Validations.ValidateVillainSet do
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
    case Ash.Changeset.get_attribute(subject, :villain_set_id) do
      # The standard allow_nil? check reports the missing value.
      nil ->
        :ok

      id ->
        case Ash.get(Sanctum.Catalog.CardSet, id, authorize?: false) do
          {:ok, %{set_type: :villain}} ->
            :ok

          {:ok, %{set_type: type}} ->
            {:error,
             field: :villain_set_id, message: "must be a villain set, got #{inspect(type)}"}

          {:error, _} ->
            {:error, field: :villain_set_id, message: "does not exist"}
        end
    end
  end
end
