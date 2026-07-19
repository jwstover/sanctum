defmodule Sanctum.Decks.Stats do
  @moduledoc """
  Read-only rollups behind the public `/stats` page.

  These are group-by aggregates over the decks table, which Ash read actions
  don't model — schemaless Ecto (the admin health snapshot's pattern) keeps
  each one a single round trip. Deck reads are public, so nothing here
  bypasses a policy that would apply through Ash.

  Deck dates use the MarvelCDB publish date when we have it (imported decks),
  falling back to our own insert time (native decks).
  """

  import Ecto.Query

  alias Sanctum.Repo

  @canonical_aspects ~w(aggression justice leadership protection pool)

  @doc "Headline counts: total decks, distinct heroes built, decks added this month."
  def totals do
    %{decks: decks, heroes: heroes} =
      Repo.one(
        from d in "decks",
          select: %{decks: count(d.id), heroes: count(d.hero_id, :distinct)}
      )

    month_start = DateTime.utc_now() |> DateTime.to_date() |> Date.beginning_of_month()

    this_month =
      Repo.one(
        from d in "decks",
          where:
            fragment(
              "coalesce(?, ?) >= ?",
              d.mcdb_date_creation,
              d.inserted_at,
              type(^month_start, :date)
            ),
          select: count(d.id)
      )

    %{decks: decks, heroes: heroes, this_month: this_month}
  end

  @doc """
  `{month, deck_count}` per calendar month, oldest first, zero-filled so time
  charts don't silently skip empty months.
  """
  def by_month do
    from(d in "decks",
      group_by: selected_as(:month),
      order_by: selected_as(:month),
      select:
        {selected_as(
           fragment(
             "date_trunc('month', coalesce(?, ?))::date",
             d.mcdb_date_creation,
             d.inserted_at
           ),
           :month
         ), count(d.id)}
    )
    |> Repo.all()
    |> fill_months()
  end

  @doc """
  Top `limit` heroes by deck count, as `{display_name, deck_count}`. Heroes
  that share a hero name (the Spider-Men, notably) get their alter ego
  appended so the rows stay distinguishable.
  """
  def per_hero(limit \\ 15) do
    rows =
      Repo.all(
        from d in "decks",
          join: h in "heroes",
          on: h.id == d.hero_id,
          group_by: [h.id, h.hero_name, h.alter_ego_name],
          order_by: [desc: count(d.id), asc: h.hero_name],
          limit: ^limit,
          select: {h.hero_name, h.alter_ego_name, count(d.id)}
      )

    dupes =
      rows
      |> Enum.frequencies_by(fn {name, _, _} -> name end)
      |> Map.filter(fn {_, n} -> n > 1 end)

    Enum.map(rows, fn {name, alter_ego, count} ->
      if Map.has_key?(dupes, name) and is_binary(alter_ego) do
        {"#{name} (#{alter_ego})", count}
      else
        {name, count}
      end
    end)
  end

  @doc """
  `{aspect, deck_count}` in canonical aspect order, with aspect-less ("basic")
  decks last. A multi-aspect deck counts once under each of its aspects.
  """
  def by_aspect do
    counts =
      Repo.query!(
        "SELECT a.aspect::text, count(*) FROM decks d CROSS JOIN LATERAL unnest(d.aspects) AS a(aspect) GROUP BY 1"
      ).rows
      |> Map.new(fn [aspect, n] -> {aspect, n} end)

    basic =
      Repo.one(
        from d in "decks",
          where: fragment("cardinality(?) = 0", d.aspects),
          select: count(d.id)
      )

    Enum.map(@canonical_aspects, &{&1, Map.get(counts, &1, 0)}) ++ [{"basic", basic}]
  end

  defp fill_months([]), do: []

  defp fill_months(rows) do
    counts = Map.new(rows)
    {first, _} = List.first(rows)
    {last, _} = List.last(rows)

    first
    |> Stream.unfold(fn month ->
      if Date.after?(month, last), do: nil, else: {month, Date.shift(month, month: 1)}
    end)
    |> Enum.map(&{&1, Map.get(counts, &1, 0)})
  end
end
