defmodule Sanctum.Decks.Uniqueness do
  @moduledoc """
  Computes a per-deck "uniqueness" score across the whole deck library.

  Every deck of a given hero shares the same ~15 fixed `:hero` signature cards,
  so those carry no signal and are excluded entirely. What remains — the chosen
  aspect and basic cards — is the deck's *choice set*. A deck is unique to the
  degree that no other deck of the same hero shares those choices.

  ## Algorithm

  A full sweep, run in one pass over the library:

  1. Load every `(deck_id, hero_id, card_id)` where the card is not a `:hero`
     card, folded into `%{deck_id => {hero_id, MapSet(card_ids)}}`.
  2. Group decks by hero — comparisons only happen within a hero.
  3. Per hero, build an inverted index `card_id => [deck_id]`, then for each deck
     do a single tally pass over its cards to get `|deck ∩ other|` for *every*
     other deck at once (decks sharing nothing never enter the tally and are
     correctly maximally unique). Jaccard similarity follows directly, and the
     score is `1 - avg(top-k nearest-neighbor similarities)`.
  4. Rank scores within each hero into a 0-100 percentile (heroes below
     `min_hero_decks` get a `nil` percentile — too few decks to rank).
  5. Write every deck's score/percentile/nearest back in a single statement.

  Cost is proportional to card co-occurrence density, not `O(decks²)`, since the
  inverted index only ever pairs decks that actually share a card.
  """

  # Heroes with fewer decks than this can't be meaningfully ranked; their decks
  # still get a raw score + nearest neighbor, but no percentile (badge hidden).
  @min_hero_decks 10

  # Compare against the average of the K closest neighbors rather than the
  # single closest — smooths the jumpiness of very small choice sets.
  @top_k 3

  @doc """
  Recompute uniqueness for every deck and persist the results.

  Options (mainly for tests):
    * `:min_hero_decks` — minimum decks in a hero group to assign percentiles.
    * `:top_k` — neighbors averaged into the similarity.

  Returns `{:ok, %{decks: total, ranked: with_percentile}}`.
  """
  def recompute_all(opts \\ []) do
    min_hero_decks = Keyword.get(opts, :min_hero_decks, @min_hero_decks)
    top_k = Keyword.get(opts, :top_k, @top_k)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    choice_sets = load_choice_sets()

    results =
      choice_sets
      |> group_by_hero()
      |> Enum.flat_map(fn {_hero_id, decks} ->
        score_hero_group(decks, min_hero_decks, top_k)
      end)

    write_scores(results, now)

    {:ok,
     %{
       decks: map_size(choice_sets),
       ranked: Enum.count(results, &(&1.percentile != nil))
     }}
  end

  @doc """
  The decks most similar to `deck` (same hero, by shared non-`:hero` cards).

  Computed on demand — cheap for a single deck, and always fresh regardless of
  when the last full sweep ran. Returns `[%{deck: deck, similarity: float}]`
  sorted most-similar first, at most `:limit` (default 6) entries, each sharing
  at least one chosen card. `deck` is loaded with the relationships a compact
  tile needs. Returns `[]` when the deck has no chosen cards.
  """
  def similar_decks(deck, opts \\ []) do
    limit = Keyword.get(opts, :limit, 6)
    sets = hero_choice_sets(deck.hero_id)
    target = Map.get(sets, deck.id, MapSet.new())

    if MapSet.size(target) == 0 do
      []
    else
      scored =
        sets
        |> Map.delete(deck.id)
        |> Enum.map(fn {id, set} -> {id, jaccard(target, set)} end)
        |> Enum.filter(fn {_id, sim} -> sim > 0 end)
        |> Enum.sort_by(fn {_id, sim} -> sim end, :desc)
        |> Enum.take(limit)

      decks_by_id = load_decks_for_display(Enum.map(scored, &elem(&1, 0)))
      Enum.flat_map(scored, &attach_deck(&1, decks_by_id))
    end
  end

  defp attach_deck({id, similarity}, decks_by_id) do
    case Map.fetch(decks_by_id, id) do
      {:ok, deck} -> [%{deck: deck, similarity: similarity}]
      :error -> []
    end
  end

  defp jaccard(a, b) do
    inter = MapSet.size(MapSet.intersection(a, b))
    union = MapSet.size(a) + MapSet.size(b) - inter
    if union == 0, do: 0.0, else: inter / union
  end

  # %{deck_id => MapSet(non-hero card_ids)} for every deck of one hero.
  # sobelow_skip ["SQL.Query"] — static query; hero id travels as a bound param.
  defp hero_choice_sets(hero_id) do
    sql = """
    SELECT dc.deck_id::text, dc.card_id::text
    FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    JOIN card_sides cs ON cs.card_id = dc.card_id AND cs.is_primary_side = true
    WHERE d.hero_id::text = $1 AND cs.ownership IS DISTINCT FROM 'hero'
    """

    %{rows: rows} = Sanctum.Repo.query!(sql, [to_string(hero_id)])

    Enum.reduce(rows, %{}, fn [deck_id, card_id], acc ->
      Map.update(acc, deck_id, MapSet.new([card_id]), &MapSet.put(&1, card_id))
    end)
  end

  defp load_decks_for_display([]), do: %{}

  defp load_decks_for_display(ids) do
    require Ash.Query

    Sanctum.Decks.Deck
    |> Ash.Query.filter(id in ^ids)
    |> Ash.Query.load([:total_card_count, hero: [:hero_side, card: [:primary_side]]])
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.id, &1})
  end

  # %{deck_id => {hero_id, MapSet(card_ids)}} for all non-`:hero` cards.
  # Decks with only hero cards (empty choice set) are absent and stay unscored.
  # sobelow_skip ["SQL.Query"] — static query, no interpolation.
  defp load_choice_sets do
    sql = """
    SELECT dc.deck_id::text, d.hero_id::text, dc.card_id::text
    FROM deck_cards dc
    JOIN decks d ON d.id = dc.deck_id
    JOIN card_sides cs ON cs.card_id = dc.card_id AND cs.is_primary_side = true
    WHERE cs.ownership IS DISTINCT FROM 'hero'
    """

    %{rows: rows} = Sanctum.Repo.query!(sql)

    Enum.reduce(rows, %{}, fn [deck_id, hero_id, card_id], acc ->
      Map.update(acc, deck_id, {hero_id, MapSet.new([card_id])}, fn {hero, set} ->
        {hero, MapSet.put(set, card_id)}
      end)
    end)
  end

  defp group_by_hero(choice_sets) do
    Enum.group_by(
      choice_sets,
      fn {_deck_id, {hero_id, _cards}} -> hero_id end,
      fn {deck_id, {_hero_id, cards}} -> {deck_id, cards} end
    )
  end

  # decks :: [{deck_id, MapSet(card_ids)}]
  defp score_hero_group(decks, min_hero_decks, top_k) do
    sizes = Map.new(decks, fn {id, cards} -> {id, MapSet.size(cards)} end)

    inverted =
      Enum.reduce(decks, %{}, fn {id, cards}, acc ->
        Enum.reduce(cards, acc, fn card, acc ->
          Map.update(acc, card, [id], &[id | &1])
        end)
      end)

    scored =
      Enum.map(decks, fn {id, cards} ->
        sims =
          id
          |> intersection_counts(cards, inverted)
          |> Enum.map(fn {other, inter} ->
            union = Map.fetch!(sizes, id) + Map.fetch!(sizes, other) - inter
            {other, inter / union}
          end)

        {score, nearest} = summarize(sims, top_k)
        %{id: id, score: score, nearest: nearest}
      end)

    assign_percentiles(scored, length(decks) >= min_hero_decks)
  end

  # `|deck ∩ other|` for every other deck that shares ≥1 card, in one pass over
  # this deck's cards via the inverted index. Decks sharing nothing never appear.
  defp intersection_counts(deck_id, cards, inverted) do
    Enum.reduce(cards, %{}, fn card, acc ->
      tally_shared(Map.fetch!(inverted, card), deck_id, acc)
    end)
  end

  defp tally_shared(deck_ids, self_id, acc) do
    Enum.reduce(deck_ids, acc, fn
      ^self_id, acc -> acc
      other, acc -> Map.update(acc, other, 1, &(&1 + 1))
    end)
  end

  # No other deck shares a card ⇒ maximally unique, no nearest neighbor.
  defp summarize([], _top_k), do: {1.0, nil}

  defp summarize(sims, top_k) do
    sorted = Enum.sort_by(sims, fn {_id, sim} -> sim end, :desc)
    {nearest_id, _sim} = hd(sorted)

    top = Enum.take(sorted, top_k)
    avg = Enum.sum(Enum.map(top, fn {_id, sim} -> sim end)) / length(top)

    {1.0 - avg, nearest_id}
  end

  defp assign_percentiles(scored, false) do
    Enum.map(scored, &Map.put(&1, :percentile, nil))
  end

  defp assign_percentiles(scored, true) do
    n = length(scored)
    scores = Enum.map(scored, & &1.score)

    Enum.map(scored, fn deck ->
      # Percentile = share of decks strictly less unique than this one. Ties
      # share a rank; a lone deck (n <= 1 can't happen here) would be top.
      below = Enum.count(scores, fn s -> s < deck.score end)
      percentile = if n <= 1, do: 100, else: round(below / (n - 1) * 100)
      Map.put(deck, :percentile, percentile)
    end)
  end

  defp write_scores([], _now), do: :ok

  # sobelow_skip ["SQL.Query"] — static query; all data travels as bound params.
  defp write_scores(results, now) do
    ids = Enum.map(results, & &1.id)
    scores = Enum.map(results, & &1.score)
    percentiles = Enum.map(results, & &1.percentile)
    nearests = Enum.map(results, & &1.nearest)

    # One statement for the whole library. Ids/nearests travel as text[] and are
    # cast to uuid in SQL (Postgrex can't encode string UUIDs into a uuid[]
    # param directly). This bypasses Ash on purpose: it's an internal computed
    # metric, not a user-facing write, and skips the hero validation.
    sql = """
    UPDATE decks AS d
    SET uniqueness_score = data.score,
        uniqueness_percentile = data.percentile,
        nearest_deck_id = data.nearest::uuid,
        uniqueness_at = $5
    FROM (
      SELECT *
      FROM unnest($1::text[], $2::float8[], $3::int[], $4::text[])
        AS t(id, score, percentile, nearest)
    ) AS data
    WHERE d.id = data.id::uuid
    """

    Sanctum.Repo.query!(sql, [ids, scores, percentiles, nearests, now])
    :ok
  end
end
