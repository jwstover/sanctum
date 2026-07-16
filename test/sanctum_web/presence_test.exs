defmodule SanctumWeb.PresenceTest do
  @moduledoc false

  # Not async: presence state is global, and other async LiveView tests
  # would bleed connected sessions into the counts asserted here.
  use SanctumWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias SanctumWeb.Presence

  test "connected LiveViews are tracked and counted", %{conn: conn} do
    base = Presence.active_sessions_count()

    {:ok, _view, _html} = live(conn, ~p"/decks")

    assert Presence.active_sessions_count() == base + 1
  end

  test "emit_active_sessions/0 emits the gauge telemetry event" do
    ref =
      :telemetry_test.attach_event_handlers(self(), [[:sanctum, :sessions, :active]])

    Presence.emit_active_sessions()

    assert_receive {[:sanctum, :sessions, :active], ^ref, %{count: count}, %{}}
    assert is_integer(count) and count >= 0
  end
end
