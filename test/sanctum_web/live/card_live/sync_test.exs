defmodule SanctumWeb.CardLive.SyncTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "renders the sync page with a start button when no sync is running", %{conn: conn} do
    # The singleton server may hold :idle or a previous test's :done state —
    # either way, no sync is running and the form must be startable.
    {:ok, _view, html} = live(conn, ~p"/cards/sync")

    assert html =~ "Card Sync"
    assert html =~ "Start sync"
    assert html =~ "Skip images"
  end

  test "renders live progress from PubSub broadcasts", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/cards/sync")

    running = %{
      status: :running,
      phase: :images,
      current: "01097b.png",
      index: 150,
      total: 3598,
      data: %{synced: 3887, failed: 0},
      images: %{uploaded: 120, skipped: 30, failed: 0},
      failures: [],
      started_at: ~U[2026-07-13 12:00:00Z],
      finished_at: nil
    }

    send(view.pid, {:card_sync, running})
    html = render(view)

    assert html =~ "Mirroring images to the bucket"
    assert html =~ "01097b.png"
    assert html =~ "150 / 3598"
    assert html =~ "3887"
    assert html =~ "Sync running…"
  end
end
