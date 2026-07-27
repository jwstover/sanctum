defmodule Sanctum.Games.DuplicateCardCleanup do
  @moduledoc """
  One-time (idempotent) cleanup of stale *duplicate* canonical cards.

  MarvelCDB reprints every basic card (Energy, Genius, Strength, and countless
  allies/events/upgrades) in later packs, flagging each reprint with a
  `duplicate_of_code`. Our sync collapses those into thin `CardAlt` rows hanging
  off the single canonical `Card` — an alt has no `CardSide`, so it never appears
  in the card pool. That's the intended model (see `Sanctum.Games.CardAlt`).

  Reprints synced *before* that handling existed were minted as full canonical
  `Card`s with their own thin `CardSide`s (missing image, resource pips, stats).
  Re-syncing never removes them — the duplicate branch only ever writes the
  `card_alts` table and leaves a pre-existing canonical row untouched. The result
  is that each such reprint exists twice: the correct `CardAlt` **and** a stale
  `Card` whose empty side pollutes the pool.

  A stale card is identified purely from our own data: **a canonical `Card` whose
  `code` also exists as a `CardAlt` row.** The alt proves the code is a reprint
  whose real data lives on a different canonical card.

  This module re-points every reference off the stale cards and deletes them:

    * `deck_cards` are re-pointed to the true canonical card. Contributions are
      aggregated per `(deck, canonical)` and summed, so a deck that already holds
      the canonical card — or holds several reprints that collapse to the same
      canonical — ends up with a single merged row (respecting the
      `unique_deck_card` index).
    * `card_alts` that were mis-pointed *at* a stale card (an old sync resolved one
      reprint to another reprint instead of the original) are re-pointed to the
      final canonical. Resolution follows the reprint chain transitively.
    * The stale `Card`s are deleted; their `CardSide`s cascade away.

  Deleting the stale cards also fixes deck-slot resolution going forward: with the
  duplicate `CardSide` gone, a reprint code resolves through its `CardAlt` to the
  real canonical instead of the empty stale side.

  Runs inside a single transaction. `run/1` defaults to a dry run that reports
  what it *would* do and rolls back; pass `dry_run: false` to commit.

      Sanctum.Games.DuplicateCardCleanup.run()                 # report only
      Sanctum.Games.DuplicateCardCleanup.run(dry_run: false)   # apply
  """

  alias Sanctum.Repo

  require Logger

  @max_chain_depth 16

  @doc """
  Runs the cleanup. Returns `{:ok, report}`.

  Options:

    * `:dry_run` (default `true`) — when true, computes the report and rolls the
      transaction back so nothing is persisted.
  """
  def run(opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, true)

    result =
      Repo.transaction(fn ->
        mapping = build_mapping()

        report =
          if map_size(mapping) == 0 do
            empty_report(dry_run?)
          else
            create_map_table(mapping)
            deck = repoint_deck_cards()
            alts = repoint_alts()
            delete_stale_cards(mapping)

            %{
              stale_cards: map_size(mapping),
              deck_rows_removed: deck.removed,
              canonical_rows_created: deck.created,
              canonical_rows_updated: deck.updated,
              alts_repointed: alts,
              dry_run: dry_run?
            }
          end

        if dry_run?, do: Repo.rollback({:dry_run, report})
        report
      end)

    report =
      case result do
        {:ok, report} -> report
        {:error, {:dry_run, report}} -> report
      end

    log_report(report)
    {:ok, report}
  end

  # ── mapping: stale card id => final canonical card id ──────────────────────

  # Builds `%{stale_card_id => final_canonical_id}` by resolving each stale card's
  # code through the alt table, following the chain until it lands on a card that
  # is not itself stale.
  defp build_mapping do
    # Every canonical card whose code also appears in card_alts is a stale reprint.
    stale_rows =
      Repo.query!("""
      SELECT c.id, c.code
      FROM cards c
      WHERE EXISTS (SELECT 1 FROM card_alts a WHERE a.code = c.code)
      """).rows
      |> Enum.map(fn [id, code] -> {uuid!(id), code} end)

    # code => canonical card_id it resolves to (the official alt's target).
    alt_target_by_code =
      Repo.query!("""
      SELECT DISTINCT ON (a.code) a.code, a.card_id
      FROM card_alts a
      WHERE a.origin = 'official'
      ORDER BY a.code
      """).rows
      |> Map.new(fn [code, card_id] -> {code, uuid!(card_id)} end)

    # id => code, so we can follow a chain when a target is itself stale.
    code_by_stale_id = Map.new(stale_rows, fn {id, code} -> {id, code} end)
    stale_ids = MapSet.new(Map.keys(code_by_stale_id))

    Map.new(stale_rows, fn {id, code} ->
      {id, resolve_final(code, alt_target_by_code, code_by_stale_id, stale_ids)}
    end)
  end

  # Follows code -> canonical target until the target is a non-stale card.
  defp resolve_final(code, alt_target_by_code, code_by_stale_id, stale_ids) do
    Enum.reduce_while(1..@max_chain_depth, code, fn _depth, current_code ->
      resolve_step(current_code, alt_target_by_code, code_by_stale_id, stale_ids)
    end)
    |> case do
      {:ok, target_id} -> target_id
      _ -> raise "reprint chain for code #{code} exceeded #{@max_chain_depth} hops"
    end
  end

  # One hop of the chain: resolve a code to its canonical target, and either halt
  # (target is a real canonical card) or continue with the target's own code
  # (target is itself a stale reprint).
  defp resolve_step(code, alt_target_by_code, code_by_stale_id, stale_ids) do
    case Map.fetch(alt_target_by_code, code) do
      {:ok, target_id} ->
        if MapSet.member?(stale_ids, target_id),
          do: {:cont, Map.fetch!(code_by_stale_id, target_id)},
          else: {:halt, {:ok, target_id}}

      :error ->
        raise "no alt target for reprint code #{code}"
    end
  end

  # Materializes the stale_id => final_id mapping into a transaction-scoped temp
  # table the re-pointing statements join against.
  defp create_map_table(mapping) do
    {stale_ids, final_ids} =
      Enum.reduce(mapping, {[], []}, fn {stale_id, final_id}, {s, f} ->
        {[stale_id | s], [final_id | f]}
      end)

    Repo.query!("""
    CREATE TEMPORARY TABLE dup_map (stale_id uuid PRIMARY KEY, final_id uuid NOT NULL)
    ON COMMIT DROP
    """)

    Repo.query!(
      """
      INSERT INTO dup_map (stale_id, final_id)
      SELECT unnest($1::text[])::uuid, unnest($2::text[])::uuid
      """,
      [stale_ids, final_ids]
    )
  end

  # ── re-point deck_cards ────────────────────────────────────────────────────

  # Aggregates every stale deck slot onto its canonical card and merges quantities.
  # Returns `%{removed, created, updated}`.
  defp repoint_deck_cards do
    # Sum stale contributions per (deck, canonical). Computed before the delete so
    # the quantities survive.
    Repo.query!("""
    CREATE TEMPORARY TABLE dc_agg ON COMMIT DROP AS
    SELECT dc.deck_id,
           m.final_id AS card_id,
           sum(dc.quantity)::bigint AS quantity,
           bool_or(dc.ignore_deck_limit) AS ignore_deck_limit
    FROM deck_cards dc
    JOIN dup_map m ON m.stale_id = dc.card_id
    GROUP BY dc.deck_id, m.final_id
    """)

    # How many aggregated targets already have a canonical row (updates) vs not
    # (inserts) — captured before the upsert changes the answer.
    [[updated, created]] =
      Repo.query!("""
      SELECT
        count(*) FILTER (WHERE EXISTS (
          SELECT 1 FROM deck_cards d WHERE d.deck_id = a.deck_id AND d.card_id = a.card_id)),
        count(*) FILTER (WHERE NOT EXISTS (
          SELECT 1 FROM deck_cards d WHERE d.deck_id = a.deck_id AND d.card_id = a.card_id))
      FROM dc_agg a
      """).rows

    removed =
      Repo.query!("""
      DELETE FROM deck_cards dc USING dup_map m WHERE dc.card_id = m.stale_id
      """).num_rows

    Repo.query!("""
    INSERT INTO deck_cards (id, deck_id, card_id, quantity, ignore_deck_limit)
    SELECT gen_random_uuid(), a.deck_id, a.card_id, a.quantity, a.ignore_deck_limit
    FROM dc_agg a
    ON CONFLICT (deck_id, card_id) DO UPDATE
      SET quantity = deck_cards.quantity + EXCLUDED.quantity,
          ignore_deck_limit = deck_cards.ignore_deck_limit OR EXCLUDED.ignore_deck_limit
    """)

    %{removed: removed, created: created, updated: updated}
  end

  # ── re-point alts that were mis-pointed at a stale card ────────────────────

  defp repoint_alts do
    Repo.query!("""
    UPDATE card_alts a SET card_id = m.final_id
    FROM dup_map m WHERE a.card_id = m.stale_id
    """).num_rows
  end

  # ── delete the stale cards (card_sides cascade) ────────────────────────────

  defp delete_stale_cards(mapping) do
    Repo.query!("DELETE FROM cards WHERE id = ANY($1::text[]::uuid[])", [Map.keys(mapping)])
  end

  # ── helpers ────────────────────────────────────────────────────────────────

  defp empty_report(dry_run?) do
    %{
      stale_cards: 0,
      deck_rows_removed: 0,
      canonical_rows_created: 0,
      canonical_rows_updated: 0,
      alts_repointed: 0,
      dry_run: dry_run?
    }
  end

  # Postgrex returns uuids as 16-byte binaries; normalize to canonical text so the
  # values round-trip cleanly back through `::uuid[]` params.
  defp uuid!(<<_::binary-size(16)>> = raw), do: Ecto.UUID.load!(raw)
  defp uuid!(str) when is_binary(str), do: str

  defp log_report(report) do
    prefix = if report.dry_run, do: "[dry run] would clean up", else: "cleaned up"

    Logger.info(
      "DuplicateCardCleanup #{prefix} #{report.stale_cards} stale duplicate card(s): " <>
        "#{report.deck_rows_removed} stale deck slot(s) removed, folded into " <>
        "#{report.canonical_rows_created} new + #{report.canonical_rows_updated} existing " <>
        "canonical deck row(s); #{report.alts_repointed} alt(s) re-pointed."
    )
  end
end
