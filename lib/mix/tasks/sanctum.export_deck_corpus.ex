defmodule Mix.Tasks.Sanctum.ExportDeckCorpus do
  @shortdoc "Exports the deck corpus to an NDJSON snapshot for archetype research"

  @moduledoc """
  Dumps decks, deck cards, and card metadata into a dated, immutable snapshot
  for the offline deck-archetype experimentation harness
  (`research/deck_archetypes/`).

      mix sanctum.export_deck_corpus
      mix sanctum.export_deck_corpus --out research/deck_archetypes/snapshots/2026-07-27

  Writes three newline-delimited JSON files plus a `SNAPSHOT.json` manifest into
  the output directory:

    * `cards.jsonl`      — one canonical card per line (primary side fields).
    * `decks.jsonl`      — one deck per line (hero, aspects, state, size, ...).
    * `deck_cards.jsonl` — one deck slot per line: `{deck_id, card_id, quantity}`.
    * `SNAPSHOT.json`    — row counts + `max(updated_at)` as the `snapshot_hash`,
                           so the Python side never compares runs across corpora.

  NDJSON (not parquet) keeps the Elixir side dependency-free — arrays (`aspects`,
  `traits`) round-trip natively and Polars reads it via `read_ndjson`. The big
  `deck_cards` table is streamed with a server-side cursor so the task stays
  flat in memory regardless of corpus size.

  `deck_cards.card_id` is already the **canonical** `Card` id: MarvelCDB reprints
  collapse into `CardAlt` rows at import and deck slots resolve to the canonical
  card, so no alt resolution happens here (mirrors `Sanctum.Decks.Uniqueness`,
  which joins `deck_cards.card_id` straight to `card_sides`). Hero cards are
  intentionally kept in the export — the harness strips `ownership == "hero"`
  itself so different runs can revisit that choice.

  Point it at real data: run under `prod_local`, or against a `pull_prod_db`
  dump, so archetypes are learned from the true deck distribution.
  """

  use Mix.Task

  alias Sanctum.Repo

  @requirements ["app.start"]

  @switches [out: :string]

  @impl true
  def run(argv) do
    {opts, _argv} = OptionParser.parse!(argv, strict: @switches)

    out = Keyword.get(opts, :out) || Path.join(default_dir(), to_string(Date.utc_today()))
    File.mkdir_p!(out)

    Mix.shell().info("Exporting deck corpus → #{out}")

    {card_count, _} = export_cards(Path.join(out, "cards.jsonl"))
    Mix.shell().info("  cards.jsonl        #{card_count} rows")

    deck_count = export_decks(Path.join(out, "decks.jsonl"))
    max_updated_at = max_deck_updated_at()
    Mix.shell().info("  decks.jsonl        #{deck_count} rows")

    slot_count = export_deck_cards(Path.join(out, "deck_cards.jsonl"))
    Mix.shell().info("  deck_cards.jsonl   #{slot_count} rows")

    hero_count = export_heroes(Path.join(out, "heroes.jsonl"))
    Mix.shell().info("  heroes.jsonl       #{hero_count} rows")

    write_manifest(Path.join(out, "SNAPSHOT.json"), %{
      cards: card_count,
      decks: deck_count,
      deck_cards: slot_count,
      heroes: hero_count,
      max_updated_at: max_updated_at
    })

    Mix.shell().info("Done. snapshot_hash written to SNAPSHOT.json")
  end

  defp default_dir, do: Path.join(~w[research deck_archetypes snapshots])

  # --- cards -----------------------------------------------------------------
  # One row per canonical card, carrying its primary side's printed fields. The
  # harness derives per-card content features (Channel C) and rules-text
  # embeddings (Channel B) from these. Stats are emitted as their bare `value`
  # (star/scaling dropped); Python coerces the text to numbers.
  #
  # `hero_locked` = the card belongs to a hero's signature set (`cards.set`
  # matches a hero's `set`). This catches signature cards that are NOT
  # ownership==:hero — the aspect-flavored ones (e.g. Spider-Woman's Pheromones,
  # ownership player + aspect leadership). They appear in ~100% of that hero's
  # decks, so like hero cards they carry no archetype signal and must be excluded
  # by the harness alongside ownership==:hero.
  # sobelow_skip ["SQL.Query"] — static query, no interpolation.
  defp export_cards(path) do
    sql = """
    SELECT c.id::text,
           cs.name,
           cs.type::text,
           cs.ownership::text,
           cs.aspect,
           cs.traits,
           cs.cost,
           cs.resource_physical_count,
           cs.resource_mental_count,
           cs.resource_energy_count,
           cs.resource_wild_count,
           cs.attack ->> 'value',
           cs.thwart ->> 'value',
           cs.defense ->> 'value',
           cs.health ->> 'value',
           cs.text,
           c.set,
           (c.set IN (SELECT set FROM heroes WHERE set IS NOT NULL)) AS hero_locked
    FROM cards c
    JOIN card_sides cs ON cs.card_id = c.id AND cs.is_primary_side = true
    """

    %{rows: rows} = Repo.query!(sql)

    count =
      write_ndjson!(path, rows, fn [
                                     id,
                                     name,
                                     type,
                                     ownership,
                                     aspect,
                                     traits,
                                     cost,
                                     phys,
                                     mental,
                                     energy,
                                     wild,
                                     atk,
                                     thw,
                                     def,
                                     hp,
                                     text,
                                     set,
                                     hero_locked
                                   ] ->
        %{
          card_id: id,
          name: name,
          type: type,
          ownership: ownership,
          aspect: aspect,
          traits: traits || [],
          cost: cost,
          set: set,
          hero_locked: hero_locked,
          resource_physical: phys,
          resource_mental: mental,
          resource_energy: energy,
          resource_wild: wild,
          atk: atk,
          thw: thw,
          def: def,
          hp: hp,
          text: text
        }
      end)

    {count, nil}
  end

  # --- decks -----------------------------------------------------------------
  # `size` (total copies) is joined in so the harness can apply `min_deck_size`
  # without a second pass.
  # sobelow_skip ["SQL.Query"] — static query, no interpolation.
  defp export_decks(path) do
    sql = """
    SELECT d.id::text,
           d.hero_id::text,
           d.aspects,
           d.state::text,
           d.visibility::text,
           d.source::text,
           COALESCE(agg.size, 0)::int
    FROM decks d
    LEFT JOIN (
      SELECT deck_id, SUM(quantity) AS size
      FROM deck_cards
      GROUP BY deck_id
    ) agg ON agg.deck_id = d.id
    """

    %{rows: rows} = Repo.query!(sql)

    write_ndjson!(path, rows, fn [id, hero_id, aspects, state, visibility, source, size] ->
      %{
        deck_id: id,
        hero_id: hero_id,
        aspects: aspects || [],
        state: state,
        visibility: visibility,
        source: source,
        size: size
      }
    end)
  end

  # --- heroes ----------------------------------------------------------------
  # One row per hero, carrying the hero-side base stats + ability text and the
  # alter-ego recover + ability text. These never appear in deck_cards (the
  # identity card isn't a deck slot), so a deck's playstyle scorer needs them
  # separately to credit base ATK/THW/DEF, hand size, and the hero/AE ability.
  # sobelow_skip ["SQL.Query"] — static query, no interpolation.
  defp export_heroes(path) do
    sql = """
    SELECT DISTINCT ON (h.id)
           h.id::text,
           h.hero_name,
           hs.attack ->> 'value',
           hs.thwart ->> 'value',
           hs.defense ->> 'value',
           hs.hand_size,
           hs.text,
           aes.recover ->> 'value',
           aes.hand_size,
           aes.text
    FROM heroes h
    LEFT JOIN card_sides hs ON hs.card_id = h.card_id AND hs.type = 'hero'
    LEFT JOIN card_sides aes ON aes.card_id = h.card_id AND aes.type = 'alter_ego'
    ORDER BY h.id
    """

    %{rows: rows} = Repo.query!(sql)

    write_ndjson!(path, rows, fn [
                                   id,
                                   name,
                                   atk,
                                   thw,
                                   def,
                                   hero_hand,
                                   hero_text,
                                   recover,
                                   ae_hand,
                                   ae_text
                                 ] ->
      %{
        hero_id: id,
        name: name,
        atk: atk,
        thw: thw,
        def: def,
        hero_hand_size: hero_hand,
        hero_text: hero_text,
        recover: recover,
        ae_hand_size: ae_hand,
        ae_text: ae_text
      }
    end)
  end

  # Max deck `updated_at` for the snapshot hash — computed in SQL to sidestep
  # struct term-ordering (NaiveDateTime fields don't sort chronologically).
  # sobelow_skip ["SQL.Query"] — static query, no interpolation.
  defp max_deck_updated_at do
    %{rows: [[max]]} = Repo.query!("SELECT MAX(updated_at) FROM decks")
    max
  end

  # --- deck_cards ------------------------------------------------------------
  # The big table (~1-2M rows). Streamed through a server-side cursor inside a
  # transaction so memory stays flat.
  # sobelow_skip ["SQL.Query"] — static query, no interpolation.
  defp export_deck_cards(path) do
    sql = "SELECT dc.deck_id::text, dc.card_id::text, dc.quantity FROM deck_cards dc"

    # timeout: :infinity — the cursor holds a connection for the whole write,
    # which easily exceeds the default 15s transaction timeout on a large table.
    {:ok, count} = Repo.transaction(fn -> stream_deck_cards(path, sql) end, timeout: :infinity)
    count
  end

  defp stream_deck_cards(path, sql) do
    stream = Ecto.Adapters.SQL.stream(Repo, sql, [], max_rows: 5_000)

    File.open!(path, [:write, :raw], fn file ->
      stream
      |> Stream.flat_map(& &1.rows)
      |> Enum.reduce(0, &write_deck_card_row(&1, &2, file))
    end)
  end

  defp write_deck_card_row([deck_id, card_id, quantity], acc, file) do
    line = Jason.encode!(%{deck_id: deck_id, card_id: card_id, quantity: quantity})
    IO.binwrite(file, [line, ?\n])
    acc + 1
  end

  # --- helpers ---------------------------------------------------------------
  # Writes `rows` as newline-delimited JSON via `mapper`, returning the count.
  # Raw + binwrite: Jason emits UTF-8 binaries (card text carries multibyte
  # glyphs like →), which a translating io device rejects with :no_translation.
  defp write_ndjson!(path, rows, mapper) do
    File.open!(path, [:write, :raw], fn file ->
      Enum.reduce(rows, 0, fn row, acc ->
        line = row |> mapper.() |> Jason.encode!()
        IO.binwrite(file, [line, ?\n])
        acc + 1
      end)
    end)
  end

  defp write_manifest(path, %{max_updated_at: max_updated_at} = counts) do
    iso = iso8601(max_updated_at)

    hash =
      case iso do
        nil -> "empty"
        stamp -> "#{counts.decks}-#{counts.deck_cards}-#{stamp}"
      end

    manifest =
      counts
      |> Map.put(:snapshot_hash, hash)
      |> Map.put(:max_updated_at, iso)

    File.write!(path, Jason.encode!(manifest, pretty: true))
  end

  defp iso8601(nil), do: nil
  defp iso8601(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
