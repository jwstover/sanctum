defmodule Sanctum.Decks.Stats do
  @moduledoc """
  Read-only rollups behind the public `/stats` page.

  These are group-by aggregates over the decks table, which Ash read actions
  don't model — schemaless Ecto (the admin health snapshot's pattern) keeps
  each one a single round trip. That bypasses the Deck visibility policy, so
  every deck query here scopes to `visibility = 'published'` by hand — the
  stats page is public and must not count private drafts.

  Deck dates use the MarvelCDB publish date when we have it (imported decks),
  falling back to our own insert time (native decks).
  """

  import Ecto.Query

  alias Sanctum.Repo

  @canonical_aspects ~w(aggression justice leadership protection pool)

  @doc """
  Headline counts: decks, decks added this month, and the catalog totals
  (unique canonical cards — reprints live on card_alts — heroes, villains).
  """
  def totals do
    month_start = DateTime.utc_now() |> DateTime.to_date() |> Date.beginning_of_month()

    this_month =
      Repo.one(
        from d in "decks",
          where: d.visibility == "published",
          where:
            fragment(
              "coalesce(?, ?) >= ?",
              d.mcdb_date_creation,
              d.inserted_at,
              type(^month_start, :date)
            ),
          select: count(d.id)
      )

    %{
      decks: Repo.one(from d in "decks", where: d.visibility == "published", select: count(d.id)),
      this_month: this_month,
      cards: count_all("cards"),
      heroes: count_all("heroes"),
      villains: count_all("villains")
    }
  end

  defp count_all(table) do
    Repo.one(from t in table, select: count(t.id))
  end

  @doc """
  `{month, deck_count}` per calendar month, oldest first, zero-filled so time
  charts don't silently skip empty months.
  """
  def by_month do
    from(d in "decks",
      where: d.visibility == "published",
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
  Every hero with at least one deck, by deck count descending, with the
  hero's brand colors (`primary`/`secondary`, nilable) and `set` for the
  gradient fallback. Heroes that share a hero name (the Spider-Men, notably)
  get their alter ego appended so the rows stay distinguishable.
  """
  def per_hero do
    rows =
      Repo.all(
        from d in "decks",
          join: h in "heroes",
          on: h.id == d.hero_id,
          where: d.visibility == "published",
          group_by: [
            h.id,
            h.hero_name,
            h.alter_ego_name,
            h.primary_color,
            h.secondary_color,
            h.set
          ],
          order_by: [desc: count(d.id), asc: h.hero_name],
          select: %{
            id: type(h.id, Ecto.UUID),
            name: h.hero_name,
            alter_ego: h.alter_ego_name,
            primary: h.primary_color,
            secondary: h.secondary_color,
            set: h.set,
            count: count(d.id)
          }
      )

    dupes =
      rows
      |> Enum.frequencies_by(& &1.name)
      |> Map.filter(fn {_, n} -> n > 1 end)

    Enum.map(rows, fn row ->
      if Map.has_key?(dupes, row.name) and is_binary(row.alter_ego) do
        %{row | name: "#{row.name} (#{row.alter_ego})"}
      else
        row
      end
    end)
  end

  @doc """
  `{aspect, deck_count}` in canonical aspect order, with aspect-less ("basic")
  decks last. A multi-aspect deck counts once under each of its aspects.
  Pass a hero id (UUID string) to scope the split to that hero's decks.
  """
  def by_aspect(hero_id \\ nil)

  def by_aspect(nil) do
    rows =
      Repo.query!(
        "SELECT a.aspect::text, count(*) FROM decks d CROSS JOIN LATERAL unnest(d.aspects) AS a(aspect) WHERE d.visibility = 'published' GROUP BY 1"
      ).rows

    basic =
      Repo.one(
        from d in "decks",
          where: d.visibility == "published",
          where: fragment("cardinality(?) = 0", d.aspects),
          select: count(d.id)
      )

    assemble_aspects(rows, basic)
  end

  def by_aspect(hero_id) do
    uuid = Ecto.UUID.dump!(hero_id)

    rows =
      Repo.query!(
        "SELECT a.aspect::text, count(*) FROM decks d CROSS JOIN LATERAL unnest(d.aspects) AS a(aspect) WHERE d.hero_id = $1 AND d.visibility = 'published' GROUP BY 1",
        [uuid]
      ).rows

    basic =
      Repo.one(
        from d in "decks",
          where: d.visibility == "published",
          where: fragment("cardinality(?) = 0", d.aspects),
          where: d.hero_id == type(^hero_id, Ecto.UUID),
          select: count(d.id)
      )

    assemble_aspects(rows, basic)
  end

  defp assemble_aspects(rows, basic) do
    counts = Map.new(rows, fn [aspect, n] -> {aspect, n} end)
    Enum.map(@canonical_aspects, &{&1, Map.get(counts, &1, 0)}) ++ [{"basic", basic}]
  end

  @doc """
  The `aspect` cards appearing in the most of the hero's decks that run that
  aspect, as `{card_id, card_name, deck_count}` (id as a UUID string, for
  linking to the card detail page). `"basic"` instead counts basic-ownership
  cards across the hero's aspect-less decks. Raises on an unknown aspect —
  validate untrusted input before calling.
  """
  def top_cards(hero_id, aspect, limit \\ 10)

  def top_cards(hero_id, "basic", limit) do
    Repo.query!(
      """
      SELECT c.id, cs.name, count(DISTINCT dc.deck_id) AS decks
      FROM deck_cards dc
      JOIN decks d ON d.id = dc.deck_id
      JOIN cards c ON c.id = dc.card_id
      JOIN card_sides cs ON cs.card_id = c.id AND cs.is_primary_side
      WHERE d.hero_id = $1
        AND d.visibility = 'published'
        AND cardinality(d.aspects) = 0
        AND cs.ownership = 'basic'
      GROUP BY c.id, cs.name
      ORDER BY decks DESC, cs.name ASC
      LIMIT $2
      """,
      [Ecto.UUID.dump!(hero_id), limit]
    ).rows
    |> Enum.map(&load_card_row/1)
  end

  def top_cards(hero_id, aspect, limit) when aspect in @canonical_aspects do
    Repo.query!(
      """
      SELECT c.id, cs.name, count(DISTINCT dc.deck_id) AS decks
      FROM deck_cards dc
      JOIN decks d ON d.id = dc.deck_id
      JOIN cards c ON c.id = dc.card_id
      JOIN card_sides cs ON cs.card_id = c.id AND cs.is_primary_side
      WHERE d.hero_id = $1
        AND d.visibility = 'published'
        AND $2 = ANY(d.aspects::text[])
        AND cs.aspect::text = $2
      GROUP BY c.id, cs.name
      ORDER BY decks DESC, cs.name ASC
      LIMIT $3
      """,
      [Ecto.UUID.dump!(hero_id), aspect, limit]
    ).rows
    |> Enum.map(&load_card_row/1)
  end

  defp load_card_row([id, name, n]), do: {Ecto.UUID.load!(id), name, n}

  @doc """
  Pack releases for timeline annotation, as `{name, product_type,
  released_on}`, oldest first: big boxes (core + campaign expansions) and
  hero packs.
  """
  def pack_releases do
    Repo.all(
      from p in "packs",
        where:
          p.product_type in ["core", "campaign_expansion", "hero_pack"] and
            not is_nil(p.released_on),
        order_by: p.released_on,
        select: {p.name, p.product_type, p.released_on}
    )
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
