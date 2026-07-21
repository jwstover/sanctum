defmodule Mix.Tasks.Sanctum.DateOpts do
  @moduledoc """
  Shared parsing of `--since`/`--until` CLI options into `Date` keyword opts
  for the deck sync/backfill mix tasks.
  """

  @doc """
  Builds a keyword list from the parsed CLI options, adding each of `keys`
  as a `Date` when present. Raises a `Mix.Error` on invalid dates.
  """
  def build(opts, keys) do
    Enum.reduce(keys, [], fn key, acc -> maybe_put_date(acc, key, opts[key]) end)
  end

  defp maybe_put_date(opts, _key, nil), do: opts

  defp maybe_put_date(opts, key, value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> Keyword.put(opts, key, date)
      {:error, _} -> Mix.raise("Invalid #{key} date: #{value} (expected YYYY-MM-DD)")
    end
  end
end
