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

  defp create_mcdb_deck(hero, mcdb_id) do
    Deck
    |> Ash.Changeset.for_create(:create, %{
      title: "Deck #{mcdb_id}",
      hero_id: hero.id,
      source: :marvelcdb,
      mcdb_id: mcdb_id,
      mcdb_type: :decklist
    })
    |> Ash.create!(authorize?: false)
  end

  defp row(id, likes, user_id \\ nil, username \\ nil) do
    %{id: id, likes: likes, user_id: user_id, username: username}
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
      <span class="social-icon-like"><span class="num">#{row.likes}</span></span>
      <span class="social-icon-favorite"><span class="num">0</span></span>
      <span class="social-icon-comment"><span class="num">0</span></span>
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

  defp parse_request(conn) do
    ["decklists", "find", page_str] = String.split(conn.request_path, "/", trim: true)
    %{"sort" => sort} = URI.decode_query(conn.query_string)
    {String.to_existing_atom(sort), String.to_integer(page_str)}
  end

  # `pages` maps `{sort, page}` to `{rows, last_page}`. Any request outside
  # the map gets an empty page (simulating past the end).
  defp stub_pages(pages) do
    test_pid = self()

    Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
      {sort, page} = parse_request(conn)
      send(test_pid, {:mcdb_request, sort, page})

      {rows, last_page} = Map.get(pages, {sort, page}, {[], nil})
      Req.Test.html(conn, page_html(rows, last_page))
    end)
  end

  defp stub_no_requests do
    Req.Test.stub(Sanctum.MarvelCdb, fn _conn ->
      flunk("expected no HTTP requests to MarvelCDB")
    end)
  end

  defp not_running, do: fn -> false end

  describe "run/1 — likes walk" do
    test "stops at the first all-zero likes page, then walks the date pages" do
      pages = %{
        {:likes, 1} => {[row("101", 20), row("102", 15)], 10},
        {:likes, 2} => {[row("103", 5), row("104", 3)], 10},
        {:likes, 3} => {[row("105", 0), row("106", 0)], 10},
        {:date, 1} => {[row("201", 1)], 5},
        {:date, 2} => {[row("202", 2)], 5}
      }

      stub_pages(pages)

      hero = create_hero()
      matched = create_mcdb_deck(hero, "101")

      assert {:ok, summary} =
               McdbSocialRefresh.run(
                 likes_max_pages: 10,
                 date_pages: 2,
                 pace_fun: fn -> :ok end,
                 backfill_running_fun: not_running()
               )

      assert summary.likes.pages == 3
      assert summary.date.pages == 2
      assert summary.stopped == :exhausted_pages

      assert_received {:mcdb_request, :likes, 1}
      assert_received {:mcdb_request, :likes, 2}
      assert_received {:mcdb_request, :likes, 3}
      refute_received {:mcdb_request, :likes, 4}
      assert_received {:mcdb_request, :date, 1}
      assert_received {:mcdb_request, :date, 2}
      refute_received {:mcdb_request, :date, 3}

      matched = Ash.get!(Deck, matched.id, authorize?: false)
      assert matched.mcdb_like_count == 20
    end

    test "stops at likes_max_pages even when every page has likes" do
      pages = %{
        {:likes, 1} => {[row("101", 20)], 10},
        {:likes, 2} => {[row("102", 15)], 10},
        {:likes, 3} => {[row("103", 10)], 10},
        {:date, 1} => {[], 1}
      }

      stub_pages(pages)

      assert {:ok, summary} =
               McdbSocialRefresh.run(
                 likes_max_pages: 2,
                 date_pages: 1,
                 pace_fun: fn -> :ok end,
                 backfill_running_fun: not_running()
               )

      assert summary.likes.pages == 2

      assert_received {:mcdb_request, :likes, 1}
      assert_received {:mcdb_request, :likes, 2}
      refute_received {:mcdb_request, :likes, 3}
    end
  end

  describe "run/1 — date walk" do
    test "stops early when the last page is reached before date_pages" do
      pages = %{
        {:likes, 1} => {[row("101", 0)], 1},
        {:date, 1} => {[row("201", 0)], 2},
        {:date, 2} => {[row("202", 0)], 2}
      }

      stub_pages(pages)

      assert {:ok, summary} =
               McdbSocialRefresh.run(
                 likes_max_pages: 5,
                 date_pages: 10,
                 pace_fun: fn -> :ok end,
                 backfill_running_fun: not_running()
               )

      assert summary.date.pages == 2

      assert_received {:mcdb_request, :date, 1}
      assert_received {:mcdb_request, :date, 2}
      refute_received {:mcdb_request, :date, 3}
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

      assert McdbSocialRefresh.run(backfill_running_fun: fn -> true end) ==
               {:skipped, :backfill_running}
    end

    test "halts mid-walk once the backfill starts, keeping earlier progress" do
      pages = %{
        {:likes, 1} => {[row("101", 20)], 10},
        {:likes, 2} => {[row("102", 15)], 10}
      }

      stub_pages(pages)

      {:ok, counter} = Agent.start_link(fn -> 0 end)

      # `run/1` checks once up front, then `walk/5` re-checks before every page
      # (including the first) — the third call is the one that should see
      # the backfill start, right before fetching likes page 2.
      backfill_running_fun = fn ->
        Agent.get_and_update(counter, fn n -> {n, n + 1} end) >= 2
      end

      assert {:ok, %{stopped: :backfill_started} = summary} =
               McdbSocialRefresh.run(
                 likes_max_pages: 10,
                 date_pages: 5,
                 pace_fun: fn -> :ok end,
                 backfill_running_fun: backfill_running_fun
               )

      assert summary.likes.pages == 1
      assert summary.date.pages == 0

      assert_received {:mcdb_request, :likes, 1}
      refute_received {:mcdb_request, :likes, 2}
    end
  end

  describe "run/1 — errors" do
    test "a fetch error halts the run, skips the date walk, and keeps earlier progress" do
      hero = create_hero()
      matched = create_mcdb_deck(hero, "101")

      test_pid = self()

      Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
        {sort, page} = parse_request(conn)
        send(test_pid, {:mcdb_request, sort, page})

        case {sort, page} do
          {:likes, 1} -> Req.Test.html(conn, page_html([row("101", 20)], 10))
          {:likes, 2} -> Plug.Conn.send_resp(conn, 503, "")
          _ -> Req.Test.html(conn, page_html([], nil))
        end
      end)

      assert {:error, {:likes, 2, _reason}} =
               McdbSocialRefresh.run(
                 likes_max_pages: 10,
                 date_pages: 5,
                 pace_fun: fn -> :ok end,
                 backfill_running_fun: not_running()
               )

      refute_received {:mcdb_request, :date, _}

      matched = Ash.get!(Deck, matched.id, authorize?: false)
      assert matched.mcdb_like_count == 20
    end
  end

  describe "McdbSocialRefreshWorker" do
    setup do
      Application.put_env(:sanctum, McdbSocialRefresh, likes_max_pages: 1, date_pages: 1)
      :ok
    end

    test "returns :ok on a successful run" do
      stub_pages(%{
        {:likes, 1} => {[row("101", 0)], 1},
        {:date, 1} => {[row("201", 0)], 1}
      })

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

    test "returns an error tuple when a page fetch fails" do
      Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
        Plug.Conn.send_resp(conn, 503, "")
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
