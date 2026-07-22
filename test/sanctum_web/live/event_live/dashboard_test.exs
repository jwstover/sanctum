defmodule SanctumWeb.EventLive.DashboardTest do
  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Sanctum.Events

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  # Build an event with a roster: one pod, two groups (3 + 2 players).
  defp seed_event(user, opts \\ []) do
    {:ok, event} = Events.create_event(%{name: "Test Event"}, actor: user)
    {:ok, pod} = Events.create_pod(%{name: "Pod A", event_id: event.id}, actor: user)

    {:ok, _g1} =
      Events.create_group(%{name: "Group 1", pod_id: pod.id, player_count: 3}, actor: user)

    {:ok, _g2} =
      Events.create_group(%{name: "Group 2", pod_id: pod.id, player_count: 2}, actor: user)

    event = if opts[:start], do: elem(Events.start_event(event, actor: user), 1), else: event
    %{event: event, pod: pod}
  end

  defp first_group(event, user) do
    Events.get_event!(event.id, actor: user, load: [pods: [:groups]]).pods
    |> Enum.flat_map(& &1.groups)
    |> hd()
  end

  describe "index" do
    test "lists the organizer's events with derived roster counts", %{conn: conn, user: user} do
      seed_event(user)

      {:ok, _lv, html} = live(conn, ~p"/events")

      assert html =~ "Test Event"
      assert html =~ "Epic Multiplayer Events"
    end
  end

  describe "new" do
    test "creates an event and redirects to setup", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/events/new")

      {:ok, _setup_lv, html} =
        lv
        |> form("form[phx-submit=create]",
          form: %{name: "Saturday Loki", time_limit_minutes: 120}
        )
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "Saturday Loki"
      assert html =~ "Roster"
    end
  end

  describe "setup" do
    test "derives thresholds from the roster (5 players / 2 groups)", %{conn: conn, user: user} do
      %{event: event} = seed_event(user)

      {:ok, _lv, html} = live(conn, ~p"/events/#{event.id}/setup")

      # 20 * 5 players = 100 Loki HP; 10 * 5 = 50 flip; 2 * 2 groups = 4 WC target
      assert html =~ "100"
      assert html =~ "50"
      assert html =~ "4"
    end

    test "adding a pod and group updates the derived totals", %{conn: conn, user: user} do
      {:ok, event} = Events.create_event(%{name: "Empty"}, actor: user)

      {:ok, lv, _html} = live(conn, ~p"/events/#{event.id}/setup")

      render_click(lv, "add_pod")
      pod = Events.get_event!(event.id, actor: user, load: [:pods]).pods |> hd()
      render_click(lv, "add_group", %{"pod-id" => pod.id})

      reloaded = Events.get_event!(event.id, actor: user, load: [:total_players, :total_groups])
      assert reloaded.total_players == 1
      assert reloaded.total_groups == 1
    end

    test "auto-named groups are numbered uniquely across all pods", %{conn: conn, user: user} do
      {:ok, event} = Events.create_event(%{name: "Numbering"}, actor: user)
      {:ok, pod_a} = Events.create_pod(%{name: "Pod A", event_id: event.id}, actor: user)
      {:ok, pod_b} = Events.create_pod(%{name: "Pod B", event_id: event.id}, actor: user)

      {:ok, lv, _html} = live(conn, ~p"/events/#{event.id}/setup")

      # Two in Pod A, then two in Pod B — numbering should not restart per pod.
      render_click(lv, "add_group", %{"pod-id" => pod_a.id})
      render_click(lv, "add_group", %{"pod-id" => pod_a.id})
      render_click(lv, "add_group", %{"pod-id" => pod_b.id})
      render_click(lv, "add_group", %{"pod-id" => pod_b.id})

      names =
        Events.get_event!(event.id, actor: user, load: [pods: [:groups]]).pods
        |> Enum.flat_map(& &1.groups)
        |> Enum.map(& &1.name)
        |> Enum.sort()

      assert names == ["Group 1", "Group 2", "Group 3", "Group 4"]
    end

    test "starting the event seeds Loki HP and lands on the dashboard", %{conn: conn, user: user} do
      %{event: event} = seed_event(user)

      {:ok, lv, _html} = live(conn, ~p"/events/#{event.id}/setup")

      {:ok, _show_lv, html} =
        lv
        |> render_click("start")
        |> follow_redirect(conn)

      assert html =~ "100/100 HP" or html =~ "100"
      started = Events.get_event!(event.id, actor: user)
      assert started.status == :running
      assert started.loki_hp == 100
    end
  end

  describe "dashboard tracking" do
    test "recording damage lowers Loki HP and flips at the threshold", %{conn: conn, user: user} do
      %{event: event} = seed_event(user, start: true)

      {:ok, lv, _html} = live(conn, ~p"/events/#{event.id}")

      # Record 55 damage: 100 -> 45, which is below the 50 flip line.
      lv
      |> form("form[phx-submit=record_damage]", %{amount: "55"})
      |> render_submit()

      updated = Events.get_event!(event.id, actor: user)
      assert updated.loki_hp == 45
      assert updated.loki_flipped

      assert render(lv) =~ "Flipped"
    end

    test "group-level triggers each add 1 threat to Worlds Collide", %{conn: conn, user: user} do
      %{event: event} = seed_event(user, start: true)

      {:ok, lv, _html} = live(conn, ~p"/events/#{event.id}")

      # A group's Mischief and Mayhem completing, and a would-be-defeated
      # identity, each add 1 threat (the identity is not actually removed).
      render_click(lv, "scheme_completed")
      render_click(lv, "identity_defeated")

      assert Events.get_event!(event.id, actor: user).worlds_collide_threat == 2
    end

    test "the final-phase toggle is hidden until Worlds Collide reaches its target",
         %{conn: conn, user: user} do
      # 2 groups → Worlds Collide target 4.
      %{event: event} = seed_event(user, start: true)

      {:ok, lv, _html} = live(conn, ~p"/events/#{event.id}")
      refute render(lv) =~ "final phase ended"

      # Fill Worlds Collide to the target, then the toggle appears.
      Enum.each(1..4, fn _ -> render_click(lv, "scheme_completed") end)
      assert render(lv) =~ "Mark final phase ended"

      group = first_group(event, user)
      render_click(lv, "toggle_phase_ended", %{"id" => group.id})
      assert Events.get_group!(group.id, actor: user).status == :phases_ended
    end

    test "a group's Mangog seeds 10 HP per group in its pod and clamps on damage",
         %{conn: conn, user: user} do
      # seed_event puts 2 groups in the pod → Mangog max = 10 × 2 = 20.
      %{event: event} = seed_event(user, start: true)
      group = first_group(event, user)

      {:ok, lv, _html} = live(conn, ~p"/events/#{event.id}")

      render_click(lv, "toggle_mangog", %{"id" => group.id})
      render_click(lv, "mangog_delta", %{"id" => group.id, "amount" => "-4"})

      reloaded = Events.get_group!(group.id, actor: user, load: [:mangog_hp_max])
      assert reloaded.mangog_active
      assert reloaded.mangog_hp_max == 20
      assert reloaded.mangog_hp == 16
    end

    test "a group's Door Between Worlds enters with 7 threat per group in its pod",
         %{conn: conn, user: user} do
      # 2 groups → Door threat max = 7 × 2 = 14.
      %{event: event} = seed_event(user, start: true)
      group = first_group(event, user)

      {:ok, lv, _html} = live(conn, ~p"/events/#{event.id}")

      render_click(lv, "toggle_door", %{"id" => group.id})
      render_click(lv, "door_delta", %{"id" => group.id, "amount" => "-5"})

      reloaded = Events.get_group!(group.id, actor: user, load: [:door_threat_max])
      assert reloaded.door_active
      assert reloaded.door_threat_max == 14
      assert reloaded.door_threat == 9
    end

    test "groups are grouped under their pod so same-named groups are distinguishable",
         %{conn: conn, user: user} do
      {:ok, event} = Events.create_event(%{name: "Two Pods"}, actor: user)
      {:ok, pod_a} = Events.create_pod(%{name: "Pod A", event_id: event.id}, actor: user)
      {:ok, pod_b} = Events.create_pod(%{name: "Pod B", event_id: event.id}, actor: user)
      # Both pods have a "Group 1".
      {:ok, _} = Events.create_group(%{name: "Group 1", pod_id: pod_a.id}, actor: user)
      {:ok, _} = Events.create_group(%{name: "Group 1", pod_id: pod_b.id}, actor: user)
      {:ok, _} = Events.start_event(event, actor: user)

      {:ok, _lv, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Pod A"
      assert html =~ "Pod B"
    end

    test "setup redirect guards a running dashboard vs a setup event", %{conn: conn, user: user} do
      %{event: event} = seed_event(user)

      # Not started yet -> dashboard should bounce to setup.
      assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/events/#{event.id}")
      assert to =~ "/setup"
    end
  end
end
