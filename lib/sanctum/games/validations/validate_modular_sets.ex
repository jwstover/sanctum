defmodule Sanctum.Games.Validations.ValidateModularSets do
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
    ids = subject |> Ash.Changeset.get_argument(:modular_sets) |> Kernel.||([]) |> Enum.uniq()

    case ids do
      [] ->
        :ok

      ids ->
        found =
          Sanctum.Catalog.CardSet
          |> Ash.Query.filter(id in ^ids and set_type == :modular)
          |> Ash.Query.select([:id])
          |> Ash.read!(authorize?: false)

        case ids -- Enum.map(found, & &1.id) do
          [] ->
            :ok

          bad ->
            {:error, field: :modular_sets, message: "must all be modular sets: #{inspect(bad)}"}
        end
    end
  end
end
