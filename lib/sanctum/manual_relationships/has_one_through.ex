defmodule Sanctum.ManualRelationships.HasOneThrough do
  @moduledoc false

  use Ash.Resource.ManualRelationship

  require Ash.Query

  def load(records, [through: through], %{query: query} = context) do
    source = context.relationship.source
    cardinality = context.relationship.cardinality

    # Build a nested load where the final hop carries the relationship's
    # query (which already has the declared relationship filter applied),
    # e.g. through: [:card, :card_sides] => [card: [card_sides: query]].
    load =
      through
      |> Enum.reverse()
      |> Enum.reduce(query, fn t, acc -> [{t, acc}] end)

    record_ids = Enum.map(records, fn r -> r.id end)

    res =
      source
      |> Ash.Query.filter(id in ^record_ids)
      |> Ash.Query.load(load)
      |> Ash.read!(actor: context.actor)
      |> Map.new(fn record ->
        value =
          Enum.reduce(through, record, fn
            _, nil -> nil
            k, r -> Map.get(r, k)
          end)

        {record.id, cast_cardinality(value, cardinality)}
      end)

    {:ok, res}
  end

  # has_one traverses a has_many at the final hop, which yields a list.
  # Reduce it to a single record (or nil) to match the declared cardinality.
  defp cast_cardinality(value, :many), do: List.wrap(value)
  defp cast_cardinality(value, _one), do: value |> List.wrap() |> List.first()
end
