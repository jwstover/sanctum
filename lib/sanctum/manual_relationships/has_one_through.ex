defmodule Sanctum.ManualRelationships.HasOneThrough do
  @moduledoc false

  use Ash.Resource.ManualRelationship

  require Ash.Query

  def load(records, [through: through], %{query: _query} = context) do
    source = context.relationship.source

    load =
      through
      |> Enum.reverse()
      |> Enum.reduce(fn t, prev ->
        [{t, [prev]}]
      end)

    record_ids = Enum.map(records, fn r -> r.id end)

    res =
      source
      |> Ash.Query.filter(id in ^record_ids)
      |> Ash.Query.load(load)
      |> Ash.read!(actor: context.actor)
      |> Map.new(fn record ->
        {record.id,
         Enum.reduce(through, record, fn
           _, nil -> nil
           k, r -> Map.get(r, k)
         end)}
      end)

    {:ok, res}
  end
end
