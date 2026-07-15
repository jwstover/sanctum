defmodule Sanctum.DeckSyncTest do
  @moduledoc false

  # async: false — the tests toggle the global `:marvel_cdb_req_options` env and
  # share the singleton `DeckSyncState` cursor row.
  use Sanctum.DataCase, async: false

  alias Sanctum.Decks
  alias Sanctum.DeckSync

  setup do
    original = Application.get_env(:sanctum, :marvel_cdb_req_options)

    # Disable Req's own transient retry so a simulated error resolves in one
    # shot — keeps these tests fast and deterministic. (`retry: false` is
    # appended last, so it overrides the `retry: :transient` the by-date call
    # passes.)
    Application.put_env(:sanctum, :marvel_cdb_req_options,
      plug: {Req.Test, Sanctum.MarvelCdb},
      retry: false
    )

    on_exit(fn -> Application.put_env(:sanctum, :marvel_cdb_req_options, original) end)
    :ok
  end

  # Stub the by-date endpoint, dispatching on the ISO date in the request path.
  # Values: `{:ok, decks}` -> 200, `:not_found` -> 404, `:server_error` -> 500
  # (MarvelCDB's empty-day quirk / outage signal), `:timeout` -> transport error.
  # An un-mapped date flunks so we can assert a date was never fetched.
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

  defp set_cursor(date), do: {:ok, _} = Decks.set_last_synced_date(date)

  defp cursor do
    {:ok, %{last_synced_date: date}} = Decks.get_deck_sync_state()
    date
  end

  defp run(opts), do: DeckSync.run([progress_fun: fn _ -> :ok end] ++ opts)

  test "advances the cursor to the last day on a fully successful run" do
    set_cursor(~D[2024-01-09])

    stub_by_date(%{
      "2024-01-10" => {:ok, []},
      "2024-01-11" => {:ok, []},
      "2024-01-12" => {:ok, []}
    })

    assert {:ok, summary} = run(since: ~D[2024-01-10], until: ~D[2024-01-12])
    assert summary.halted == nil
    assert summary.processed == 3
    assert cursor() == ~D[2024-01-12]
  end

  test "treats a 404 as an empty synced day, not a failure" do
    set_cursor(~D[2024-01-09])

    stub_by_date(%{
      "2024-01-10" => {:ok, []},
      "2024-01-11" => :not_found,
      "2024-01-12" => {:ok, []}
    })

    assert {:ok, summary} = run(since: ~D[2024-01-10], until: ~D[2024-01-12])
    assert summary.halted == nil
    assert summary.failed == 0
    assert summary.processed == 3
    # Cursor advances past the empty (404) day.
    assert cursor() == ~D[2024-01-12]
  end

  test "treats a 500 as an empty day when the endpoint is otherwise healthy" do
    set_cursor(~D[2024-01-09])

    # 2024-01-01 is the canary the health probe fetches on each 500; serving it
    # proves the endpoint is up, so the 500 on 2024-01-11 means "no decks".
    stub_by_date(%{
      "2024-01-01" => {:ok, []},
      "2024-01-10" => {:ok, []},
      "2024-01-11" => :server_error,
      "2024-01-12" => {:ok, []}
    })

    assert {:ok, summary} = run(since: ~D[2024-01-10], until: ~D[2024-01-12])
    assert summary.halted == nil
    assert summary.failed == 0
    assert summary.processed == 3
    # Cursor advances past the 500 (empty) day rather than wedging on it.
    assert cursor() == ~D[2024-01-12]
  end

  test "halts on a 500 when the endpoint itself is unhealthy (real outage)" do
    set_cursor(~D[2024-01-09])

    # Canary also 500s → the endpoint is down, not just this date. 2024-01-12 is
    # left unstubbed: reaching it would flunk, proving the walk halted.
    stub_by_date(%{
      "2024-01-01" => :server_error,
      "2024-01-10" => {:ok, []},
      "2024-01-11" => :server_error
    })

    assert {:error, summary} = run(since: ~D[2024-01-10], until: ~D[2024-01-12])
    assert summary.halted.date == ~D[2024-01-11]
    assert summary.processed == 1
    # Cursor stops at the last successfully-fetched day so the next run resumes.
    assert cursor() == ~D[2024-01-10]
  end

  test "halts on a transient failure and checkpoints at the last good day" do
    set_cursor(~D[2024-01-09])

    # 2024-01-13 is intentionally left unstubbed: reaching it would flunk,
    # proving the walk stopped at the first failure.
    stub_by_date(%{
      "2024-01-10" => {:ok, []},
      "2024-01-11" => {:ok, []},
      "2024-01-12" => :timeout
    })

    assert {:error, summary} = run(since: ~D[2024-01-10], until: ~D[2024-01-13])
    assert summary.halted.date == ~D[2024-01-12]
    assert summary.processed == 2
    # Cursor stops at the last successfully-fetched day so the next run resumes.
    assert cursor() == ~D[2024-01-11]
  end

  test "never rewinds the cursor when the failure is at the first day" do
    set_cursor(~D[2024-01-11])

    stub_by_date(%{"2024-01-10" => :timeout})

    assert {:error, summary} = run(since: ~D[2024-01-10], until: ~D[2024-01-12])
    assert summary.halted.date == ~D[2024-01-10]
    assert summary.processed == 0
    # Nothing fetched successfully → cursor left untouched (no rewind).
    assert cursor() == ~D[2024-01-11]
  end

  test "never rewinds the cursor on a historical backfill of older dates" do
    set_cursor(~D[2024-06-01])

    stub_by_date(%{
      "2024-01-10" => {:ok, []},
      "2024-01-11" => {:ok, []}
    })

    assert {:ok, _summary} = run(since: ~D[2024-01-10], until: ~D[2024-01-11])
    # Older days synced, but the frontier must not move backward.
    assert cursor() == ~D[2024-06-01]
  end
end
