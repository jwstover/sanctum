defmodule Sanctum.Search.Values do
  @moduledoc """
  Data-driven autocomplete vocabularies for the search query language:
  distinct traits, card sets, packs, and hero/alter-ego names.

  Each list comes from the database on first use and is then served from
  `Sanctum.Search.ValueCache` (per-node, 10-minute TTL) — these are small,
  slow-moving catalogs that only change on card sync or deck import, so a
  brief staleness window is fine and keeps the suggest path allocation-free.

  Field registries reference these as `values_fun`; they are only invoked
  when the cursor is actually in that field's value position.
  """

  alias Sanctum.Search.ValueCache

  # All queries below are constant strings — no user input ever reaches them
  # (each `Sanctum.Repo.query!` call takes a literal, which Sobelow verifies).

  @doc "Distinct card traits (\"Avenger\", \"Accuser Corps\", \"A.I.M.\", …)."
  @spec traits() :: [String.t()]
  def traits do
    ValueCache.fetch(:traits, fn ->
      Sanctum.Repo.query!("SELECT DISTINCT unnest(traits) FROM card_sides ORDER BY 1")
      |> clean_rows()
    end)
  end

  @doc "Distinct card set slugs (\"age_of_apocalypse\", …)."
  @spec sets() :: [String.t()]
  def sets do
    ValueCache.fetch(:sets, fn ->
      Sanctum.Repo.query!("SELECT DISTINCT set FROM cards WHERE set IS NOT NULL ORDER BY 1")
      |> clean_rows()
    end)
  end

  @doc "Distinct pack codes (\"core\", \"aoa\", …)."
  @spec packs() :: [String.t()]
  def packs do
    ValueCache.fetch(:packs, fn ->
      Sanctum.Repo.query!("SELECT DISTINCT pack FROM cards WHERE pack IS NOT NULL ORDER BY 1")
      |> clean_rows()
    end)
  end

  @doc """
  Hero and alter-ego names, merged and sorted — the deck `hero:` field
  matches either, so both complete.
  """
  @spec heroes() :: [String.t()]
  def heroes do
    ValueCache.fetch(:heroes, fn ->
      Sanctum.Repo.query!("SELECT hero_name, alter_ego_name FROM heroes")
      |> clean_rows()
      |> Enum.uniq()
      |> Enum.sort()
    end)
  end

  defp clean_rows(%{rows: rows}) do
    rows
    |> List.flatten()
    |> Enum.reject(&(&1 in [nil, ""]))
  end
end
