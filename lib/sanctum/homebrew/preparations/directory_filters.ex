defmodule Sanctum.Homebrew.Preparations.DirectoryFilters do
  @moduledoc """
  Applies the public set directory's optional facets (`HomebrewSet
  :directory`): kind, creator, tag and recency. Each facet that is set
  narrows the result, so they combine with AND; unset facets are no-ops.

  The `"other"` kind is a catch-all: an unclassified set (no kind), the
  official `other` kind, and every project-scoped custom kind all land
  there, so no published set is unreachable through the kind facet.
  """

  use Ash.Resource.Preparation

  require Ash.Query

  @recency_days %{"week" => 7, "month" => 30, "year" => 365}

  @doc "Recency facet values, mapped to their window in days."
  def recency_days, do: @recency_days

  @impl true
  def prepare(query, _opts, _context) do
    query
    |> filter_kind(Ash.Query.get_argument(query, :kind))
    |> filter_creator(Ash.Query.get_argument(query, :creator))
    |> filter_tag(Ash.Query.get_argument(query, :tag))
    |> filter_recency(Ash.Query.get_argument(query, :recency))
  end

  defp filter_kind(query, blank) when blank in [nil, ""], do: query

  defp filter_kind(query, "other") do
    Ash.Query.filter(
      query,
      is_nil(set_kind_id) or exists(set_kind, key == "other" or origin == :custom)
    )
  end

  defp filter_kind(query, key) do
    Ash.Query.filter(query, exists(set_kind, origin == :official and key == ^key))
  end

  defp filter_creator(query, blank) when blank in [nil, ""], do: query

  defp filter_creator(query, username) do
    Ash.Query.filter(query, exists(creator, username == ^username))
  end

  defp filter_tag(query, blank) when blank in [nil, ""], do: query

  defp filter_tag(query, tag) do
    Ash.Query.filter(query, fragment("? = ANY(?)", ^tag, tags))
  end

  defp filter_recency(query, recency) do
    case Map.fetch(@recency_days, recency) do
      {:ok, days} -> Ash.Query.filter(query, attested_at >= ago(^days, :day))
      :error -> query
    end
  end
end
