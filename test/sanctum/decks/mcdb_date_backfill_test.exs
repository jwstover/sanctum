defmodule Sanctum.Decks.McdbDateBackfillTest do
  @moduledoc false

  # async: false — the tests toggle the global `:marvel_cdb_req_options` env.
  use Sanctum.DataCase, async: false

  import Ecto.Query

  alias Sanctum.Decks.Deck
  alias Sanctum.Decks.McdbDateBackfill

  setup do
    original = Application.get_env(:sanctum, :marvel_cdb_req_options)

    # Disable Req's own transient retry so a simulated error resolves in one
    # shot — keeps these tests fast and deterministic.
    Application.put_env(:sanctum, :marvel_cdb_req_options,
      plug: {Req.Test, Sanctum.MarvelCdb},
      retry: false
    )

    on_exit(fn -> Application.put_env(:sanctum, :marvel_cdb_req_options, original) end)
    :ok
  end

  # Stub the by-date endpoint, dispatching on the ISO date in the request path
  # (same shape as Sanctum.DeckSyncTest).
  defp stub_by_date(responses) do
    Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
      date = conn.request_path |> String.split("/") |> List.last()

      case Map.fetch(responses, date) do
        {:ok, {:ok, decks}} -> Req.Test.json(conn, decks)
        {:ok, :not_found} -> conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{})
        {:ok, :server_error} -> conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{})
        {:ok, :timeout} -> Req.Test.transport_error(conn, :timeout)
        :error -> flunk("unexpected fetch for #{date}")
      end
    end)
  end

  defp create_hero do
    hero_card = create(Sanctum.Games.Card)

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: hero_card.id,
        name: "Backfill Hero",
        type: :hero,
        code: "#{hero_card.code}a",
        side_identifier: "A",
        is_primary_side: true
      }
    )

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: hero_card.id,
        name: "Backfill Alter Ego",
        type: :alter_ego,
        code: "#{hero_card.code}b",
        side_identifier: "B",
        is_primary_side: false
      }
    )

    {:ok, hero} =
      Sanctum.Heroes.find_or_create_hero(%{
        hero_name: "Backfill Hero",
        alter_ego_name: "Backfill Alter Ego",
        set: hero_card.set,
        base_code: hero_card.base_code,
        card_id: hero_card.id
      })

    hero
  end

  defp create_mcdb_deck(hero, mcdb_id, attrs \\ %{}) do
    Deck
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(
        %{
          title: "Deck #{mcdb_id}",
          hero_id: hero.id,
          source: :marvelcdb,
          mcdb_id: mcdb_id,
          mcdb_type: :decklist
        },
        attrs
      )
    )
    |> Ash.create!(authorize?: false)
  end

  # Push updated_at into the past so a spurious bump can't hide inside the
  # same-second cast window of :utc_datetime.
  defp age(deck, timestamp) do
    Sanctum.Repo.update_all(from(d in Deck, where: d.id == ^deck.id),
      set: [updated_at: timestamp]
    )

    Ash.get!(Deck, deck.id, authorize?: false)
  end

  defp run(opts), do: McdbDateBackfill.run([progress_fun: fn _ -> :ok end] ++ opts)

  test "fills missing dates from the payload without touching updated_at" do
    hero = create_hero()
    aged_at = ~U[2023-06-01 12:00:00Z]

    missing = create_mcdb_deck(hero, "100") |> age(aged_at)

    already_set =
      create_mcdb_deck(hero, "101", %{
        mcdb_date_creation: ~U[2020-05-05 05:05:05Z],
        mcdb_date_update: ~U[2020-06-06 06:06:06Z]
      })

    # Same MarvelCDB id in the other id space — must not be touched by a
    # decklist backfill.
    private = create_mcdb_deck(hero, "100", %{mcdb_type: :deck})

    stub_by_date(%{
      "2024-01-15" =>
        {:ok,
         [
           %{
             "id" => 100,
             "date_creation" => "2024-01-15T00:10:13+00:00",
             "date_update" => "2024-01-21T16:02:07+00:00"
           },
           %{
             "id" => 101,
             "date_creation" => "2024-01-15T01:00:00+00:00",
             "date_update" => "2024-01-15T01:00:00+00:00"
           },
           # A deck we never imported — must be skipped, not created.
           %{
             "id" => 999,
             "date_creation" => "2024-01-15T02:00:00+00:00",
             "date_update" => "2024-01-15T02:00:00+00:00"
           }
         ]}
    })

    assert {:ok, summary} = run(since: ~D[2024-01-15], until: ~D[2024-01-15])
    assert summary == %{days: 1, processed: 1, updated: 1, halted: nil}

    missing = Ash.get!(Deck, missing.id, authorize?: false)
    assert missing.mcdb_date_creation == ~U[2024-01-15 00:10:13Z]
    assert missing.mcdb_date_update == ~U[2024-01-21 16:02:07Z]
    assert DateTime.compare(missing.updated_at, aged_at) == :eq

    # Rows that already have dates keep them.
    already_set = Ash.get!(Deck, already_set.id, authorize?: false)
    assert already_set.mcdb_date_creation == ~U[2020-05-05 05:05:05Z]
    assert already_set.mcdb_date_update == ~U[2020-06-06 06:06:06Z]

    # The :deck-space row with the same id is untouched.
    private = Ash.get!(Deck, private.id, authorize?: false)
    assert private.mcdb_date_update == nil
  end

  test "treats a 404 and a healthy-endpoint 500 as empty days" do
    # 2024-01-01 is the canary the health probe fetches on the 500.
    stub_by_date(%{
      "2024-01-01" => {:ok, []},
      "2024-01-10" => :not_found,
      "2024-01-11" => :server_error
    })

    assert {:ok, summary} = run(since: ~D[2024-01-10], until: ~D[2024-01-11])
    assert summary == %{days: 2, processed: 2, updated: 0, halted: nil}
  end

  test "halts on a transient failure and reports the day it stopped at" do
    # 2024-01-12 is intentionally left unstubbed: reaching it would flunk,
    # proving the walk stopped at the first failure.
    stub_by_date(%{
      "2024-01-10" => {:ok, []},
      "2024-01-11" => :timeout
    })

    assert {:error, summary} = run(since: ~D[2024-01-10], until: ~D[2024-01-12])
    assert summary.halted.date == ~D[2024-01-11]
    assert summary.processed == 1
  end
end
