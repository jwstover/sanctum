defmodule Sanctum.Decks.McdbSocialRefreshTest do
  @moduledoc false

  # async: false — the tests toggle the global `:marvel_cdb_req_options` env
  # and insert real `oban_jobs` rows.
  use Sanctum.DataCase, async: false
  use Oban.Testing, repo: Sanctum.Repo

  alias Sanctum.Decks.Deck
  alias Sanctum.Decks.McdbSocialRefresh
  alias Sanctum.Decks.McdbSocialRefreshWorker

  setup do
    original = Application.get_env(:sanctum, :marvel_cdb_req_options)
    original_pace = Application.get_env(:sanctum, Sanctum.Decks.McdbScrapeWorker)
    original_refresh_config = Application.get_env(:sanctum, McdbSocialRefresh)

    Application.put_env(:sanctum, :marvel_cdb_req_options,
      plug: {Req.Test, Sanctum.MarvelCdb},
      retry: false
    )

    Application.put_env(:sanctum, Sanctum.Decks.McdbScrapeWorker, pace_seconds: 0..0)

    on_exit(fn ->
      Application.put_env(:sanctum, :marvel_cdb_req_options, original)
      put_or_delete_env(Sanctum.Decks.McdbScrapeWorker, original_pace)
      put_or_delete_env(McdbSocialRefresh, original_refresh_config)
    end)

    :ok
  end

  defp put_or_delete_env(key, nil), do: Application.delete_env(:sanctum, key)
  defp put_or_delete_env(key, value), do: Application.put_env(:sanctum, key, value)

  defp create_hero do
    hero_card = create(Sanctum.Games.Card)

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: hero_card.id,
        name: "Refresh Hero",
        type: :hero,
        code: "#{hero_card.code}a",
        side_identifier: "A",
        is_primary_side: true
      }
    )

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: hero_card.id,
        name: "Refresh Alter Ego",
        type: :alter_ego,
        code: "#{hero_card.code}b",
        side_identifier: "B",
        is_primary_side: false
      }
    )

    {:ok, hero} =
      Sanctum.Heroes.find_or_create_hero(%{
        hero_name: "Refresh Hero",
        alter_ego_name: "Refresh Alter Ego",
        set: hero_card.set,
        base_code: hero_card.base_code,
        card_id: hero_card.id
      })

    hero
  end

  @today ~D[2026-10-20]

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

  defp create_user(mcdb_user_id, attrs \\ %{}) do
    {:ok, user} =
      Sanctum.Decks.find_or_create_mcdb_user(
        Map.merge(%{mcdb_user_id: mcdb_user_id}, attrs),
        authorize?: false
      )

    user
  end

  defp days_ago(n), do: DateTime.new!(Date.add(@today, -n), ~T[12:00:00], "Etc/UTC")

  # A deck authored by a username-less user, created `age` days before @today.
  defp pending_deck(hero, mcdb_id, mcdb_user_id, age \\ 1) do
    user = create_user(mcdb_user_id)

    create_mcdb_deck(hero, mcdb_id, %{
      mcdb_user_id: user.id,
      mcdb_date_creation: days_ago(age)
    })
  end

  defp row(id, user_id, username) do
    %{id: id, user_id: user_id, username: username}
  end

  defp box_html(row) do
    author =
      if row.user_id do
        ~s(<span class="username">by <a href="/user/profile/#{row.user_id}/x" class="username">#{row.username}</a></span>)
      else
        ""
      end

    """
    <div class="box">
      <h4><a href="/decklist/view/#{row.id}/x">Deck #{row.id}</a></h4>
      <span class="social-icon-like"><span class="num">99</span></span>
      #{author}
    </div>
    """
  end

  defp page_html(rows, last_page) do
    boxes = Enum.map_join(rows, "\n", &box_html/1)

    """
    <ul class="pagination pagination-sm">
      <li><a href="/decklists/find?sort=date">1</a></li>
      <li><a href="/decklists/find/#{last_page}?sort=date">#{last_page}</a></li>
    </ul>
    <div class="decklists">
    #{boxes}
    </div>
    """
  end

  defp parse_page(conn) do
    ["decklists", "find", page_str] = String.split(conn.request_path, "/", trim: true)
    String.to_integer(page_str)
  end

  # One stub for the whole run. `by_date` maps ISO date -> `{:ok, decks}` |
  # `:not_found` | `:server_error` (unmapped dates are empty days); `pages`
  # maps page number -> `{rows, last_page}` (anything else is an empty page,
  # `fail_page` 503s). Every request is reported as `{:mcdb_request, ...}`.
  defp stub_mcdb(opts \\ []) do
    by_date = Keyword.get(opts, :by_date, %{})
    pages = Keyword.get(opts, :pages, %{})
    fail_page = Keyword.get(opts, :fail_page)
    test_pid = self()

    Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
      case conn.request_path do
        "/api/public/decklists/by_date/" <> date ->
          send(test_pid, {:mcdb_request, :by_date, date})
          respond_by_date(conn, Map.get(by_date, date, {:ok, []}))

        "/decklists/find/" <> _ ->
          page = parse_page(conn)
          send(test_pid, {:mcdb_request, :page, page})

          respond_page(conn, page, pages, fail_page)
      end
    end)
  end

  defp respond_page(conn, page, _pages, page), do: Plug.Conn.send_resp(conn, 503, "")

  defp respond_page(conn, page, pages, _fail_page) do
    {rows, last_page} = Map.get(pages, page, {[], nil})
    Req.Test.html(conn, page_html(rows, last_page))
  end

  defp respond_by_date(conn, {:ok, decks}), do: Req.Test.json(conn, decks)

  defp respond_by_date(conn, :not_found),
    do: conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{})

  defp respond_by_date(conn, :server_error),
    do: conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{})

  defp stub_no_requests do
    Req.Test.stub(Sanctum.MarvelCdb, fn _conn ->
      flunk("expected no HTTP requests to MarvelCDB")
    end)
  end

  defp not_running, do: fn -> false end

  defp run(opts) do
    McdbSocialRefresh.run(
      Keyword.merge(
        [
          today: @today,
          recent_like_days: 0,
          pace_fun: fn -> :ok end,
          backfill_running_fun: not_running()
        ],
        opts
      )
    )
  end

  describe "run/1 — recent like counts" do
    test "fetches by_date for the window ending yesterday and updates held decks only" do
      hero = create_hero()
      held = create_mcdb_deck(hero, "101")
      untouched = create_mcdb_deck(hero, "102", %{mcdb_like_count: 5})

      stub_mcdb(
        by_date: %{
          "2026-10-18" =>
            {:ok, [%{"id" => 101, "like_count" => 12}, %{"id" => 999, "like_count" => 3}]},
          "2026-10-19" => {:ok, [%{"id" => 102}]}
        }
      )

      assert {:ok, %{recent_likes: likes}} = run(recent_like_days: 3)

      assert likes.days == 3
      assert likes.decklists == 3
      assert likes.matched == 2
      assert likes.missing_like_count == 1

      assert_received {:mcdb_request, :by_date, "2026-10-17"}
      assert_received {:mcdb_request, :by_date, "2026-10-18"}
      assert_received {:mcdb_request, :by_date, "2026-10-19"}
      refute_received {:mcdb_request, :by_date, "2026-10-20"}

      assert Ash.get!(Deck, held.id, authorize?: false).mcdb_like_count == 12
      # No like_count in the payload: never read as 0.
      assert Ash.get!(Deck, untouched.id, authorize?: false).mcdb_like_count == 5
    end

    test "a 404 day is empty" do
      stub_mcdb(by_date: %{"2026-10-19" => :not_found})
      assert {:ok, %{recent_likes: %{days: 1, decklists: 0}}} = run(recent_like_days: 1)
    end

    test "a 500 day with a healthy canary is empty" do
      stub_mcdb(
        by_date: %{
          "2026-10-19" => :server_error,
          "2024-01-01" => {:ok, [%{"id" => 1}]}
        }
      )

      assert {:ok, %{recent_likes: %{days: 1, decklists: 0}}} = run(recent_like_days: 1)
    end

    test "a 500 day with an unhealthy canary halts before any list page" do
      hero = create_hero()
      pending_deck(hero, "101", 1)

      stub_mcdb(by_date: %{"2026-10-19" => :server_error, "2024-01-01" => :server_error})

      assert {:error, {:recent_likes, ~D[2026-10-19], _}} = run(recent_like_days: 1)
      refute_received {:mcdb_request, :page, _}
    end
  end

  describe "run/1 — usernames" do
    test "makes no list-page request when no author is pending" do
      stub_no_requests()

      assert {:ok, %{usernames: usernames}} = run([])
      assert usernames.stopped == :nothing_pending
      assert usernames.pending == 0
    end

    test "walks until the pending author is filled, then stops" do
      hero = create_hero()
      pending_deck(hero, "101", 7001)

      stub_mcdb(
        pages: %{
          1 => {[row("100", 7000, "known")], 10},
          2 => {[row("101", 7001, "newbie")], 10},
          3 => {[row("102", 7002, "later")], 10}
        }
      )

      # Page 1's author isn't pending (no held deck), so it can't end the walk.
      assert {:ok, %{usernames: usernames}} = run([])

      assert usernames.stopped == :all_known
      assert usernames.pages == 2
      assert usernames.remaining == 0
      assert_received {:mcdb_request, :page, 1}
      assert_received {:mcdb_request, :page, 2}
      refute_received {:mcdb_request, :page, 3}

      assert create_user(7001).username == "newbie"
    end

    test "ignores authors whose decklists are older than the lookback" do
      hero = create_hero()
      pending_deck(hero, "101", 7001, 30)

      stub_no_requests()

      assert {:ok, %{usernames: %{stopped: :nothing_pending}}} = run([])
    end

    test "stops at the page cap when an author is never found" do
      hero = create_hero()
      pending_deck(hero, "101", 7001)

      stub_mcdb(
        pages: %{
          1 => {[row("500", 8000, "a")], 10},
          2 => {[row("501", 8001, "b")], 10},
          3 => {[row("502", 8002, "c")], 10}
        }
      )

      assert {:ok, %{usernames: usernames}} = run(username_max_pages: 2)
      assert usernames.stopped == :exhausted_pages
      assert usernames.remaining == 1
      assert usernames.pages == 2
      refute_received {:mcdb_request, :page, 3}
    end

    test "list-page rows never change mcdb_like_count" do
      hero = create_hero()
      deck = pending_deck(hero, "101", 7001)

      stub_mcdb(pages: %{1 => {[row("101", 7001, "newbie")], 1}})

      assert {:ok, _} = run([])
      assert Ash.get!(Deck, deck.id, authorize?: false).mcdb_like_count == 0
    end
  end

  describe "backfill_running?/0" do
    defp insert_backfill_job!(state, attrs \\ %{}) do
      job_attrs =
        Map.merge(%{worker: "Sanctum.Decks.McdbScrapeWorker", queue: "mcdb_scrape"}, attrs)

      %Oban.Job{}
      |> Ecto.Changeset.change(job_attrs)
      |> Ecto.Changeset.change(state: state)
      |> Ecto.Changeset.put_change(:args, %{})
      |> Sanctum.Repo.insert!()
    end

    test "true when the backfill has an available or scheduled job" do
      insert_backfill_job!("available")
      assert McdbSocialRefresh.backfill_running?()
    end

    test "true when the backfill is scheduled" do
      insert_backfill_job!("scheduled", %{scheduled_at: DateTime.add(DateTime.utc_now(), 60)})
      assert McdbSocialRefresh.backfill_running?()
    end

    test "false when only a completed, discarded, or cancelled job exists" do
      insert_backfill_job!("completed")
      insert_backfill_job!("discarded")
      insert_backfill_job!("cancelled")
      refute McdbSocialRefresh.backfill_running?()
    end

    test "false when no backfill job exists" do
      refute McdbSocialRefresh.backfill_running?()
    end
  end

  describe "run/1 — yields to the backfill" do
    test "skips entirely and makes no HTTP requests when the backfill is running" do
      stub_no_requests()

      assert McdbSocialRefresh.run(recent_like_days: 3, backfill_running_fun: fn -> true end) ==
               {:skipped, :backfill_running}
    end

    test "halts the username walk once the backfill starts" do
      hero = create_hero()
      pending_deck(hero, "101", 7001)

      stub_mcdb(pages: %{1 => {[row("500", 8000, "a")], 10}, 2 => {[row("501", 8001, "b")], 10}})

      {:ok, counter} = Agent.start_link(fn -> 0 end)

      # One up-front check, then one before each page: the third call sees the
      # backfill start, right before page 2.
      backfill_running_fun = fn ->
        Agent.get_and_update(counter, fn n -> {n, n + 1} end) >= 2
      end

      assert {:ok, %{usernames: %{stopped: :backfill_started, pages: 1}}} =
               run(backfill_running_fun: backfill_running_fun)

      assert_received {:mcdb_request, :page, 1}
      refute_received {:mcdb_request, :page, 2}
    end
  end

  describe "run/1 — errors" do
    test "a list-page failure halts the run, keeping earlier like counts" do
      hero = create_hero()
      held = create_mcdb_deck(hero, "101")
      pending_deck(hero, "102", 7001)

      stub_mcdb(
        by_date: %{"2026-10-19" => {:ok, [%{"id" => 101, "like_count" => 9}]}},
        pages: %{1 => {[row("500", 8000, "a")], 10}},
        fail_page: 2
      )

      assert {:error, {:usernames, 2, _reason}} = run(recent_like_days: 1)
      assert Ash.get!(Deck, held.id, authorize?: false).mcdb_like_count == 9
    end
  end

  describe "McdbSocialRefreshWorker" do
    setup do
      Application.put_env(:sanctum, McdbSocialRefresh, username_max_pages: 1)
      stub_mcdb()
      :ok
    end

    test "returns :ok on a successful run" do
      assert :ok = perform_job(McdbSocialRefreshWorker, %{})
    end

    test "returns :ok when the backfill is running (skip, not a failure)" do
      Sanctum.Repo.insert!(
        %Oban.Job{}
        |> Ecto.Changeset.change(worker: "Sanctum.Decks.McdbScrapeWorker", queue: "mcdb_scrape")
        |> Ecto.Changeset.change(state: "available")
        |> Ecto.Changeset.put_change(:args, %{})
      )

      stub_no_requests()

      assert :ok = perform_job(McdbSocialRefreshWorker, %{})
    end

    test "returns an error tuple when the by_date fetch fails" do
      Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
        Plug.Conn.send_resp(conn, 500, "")
      end)

      assert {:error, _reason} = perform_job(McdbSocialRefreshWorker, %{})
    end
  end

  describe "crontab" do
    test "schedules the daily social refresh" do
      crontab =
        :sanctum
        |> Application.fetch_env!(Oban)
        |> Keyword.fetch!(:plugins)
        |> Enum.find_value(fn
          {Oban.Plugins.Cron, opts} -> Keyword.fetch!(opts, :crontab)
          _ -> nil
        end)

      assert Enum.any?(crontab, fn {_expr, worker} -> worker == McdbSocialRefreshWorker end)
    end
  end
end
