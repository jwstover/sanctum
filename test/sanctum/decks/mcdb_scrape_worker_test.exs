defmodule Sanctum.Decks.McdbScrapeWorkerTest do
  @moduledoc false

  # async: false — the tests toggle the global `:marvel_cdb_req_options` env
  # and touch the singleton `mcdb_scrape_state` row.
  use Sanctum.DataCase, async: false
  use Oban.Testing, repo: Sanctum.Repo

  import Ecto.Query, only: [from: 2]

  require Ash.Query

  alias Sanctum.Decks
  alias Sanctum.Decks.Deck
  alias Sanctum.Decks.McdbScrape
  alias Sanctum.Decks.McdbScrapeWorker

  setup do
    original = Application.get_env(:sanctum, :marvel_cdb_req_options)

    Application.put_env(:sanctum, :marvel_cdb_req_options,
      plug: {Req.Test, Sanctum.MarvelCdb},
      retry: false
    )

    on_exit(fn -> Application.put_env(:sanctum, :marvel_cdb_req_options, original) end)
    :ok
  end

  defp create_hero do
    hero_card = create(Sanctum.Games.Card)

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: hero_card.id,
        name: "Scrape Hero",
        type: :hero,
        code: "#{hero_card.code}a",
        side_identifier: "A",
        is_primary_side: true
      }
    )

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: hero_card.id,
        name: "Scrape Alter Ego",
        type: :alter_ego,
        code: "#{hero_card.code}b",
        side_identifier: "B",
        is_primary_side: false
      }
    )

    {:ok, hero} =
      Sanctum.Heroes.find_or_create_hero(%{
        hero_name: "Scrape Hero",
        alter_ego_name: "Scrape Alter Ego",
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

  defp row(id, opts \\ []) do
    %{
      decklist_id: to_string(id),
      user_id: Keyword.get(opts, :user_id, id + 900_000),
      username: Keyword.get(opts, :username, "user#{id}"),
      like_count: Keyword.get(opts, :like_count, 0)
    }
  end

  defp box_html(%{decklist_id: id, user_id: user_id, username: username} = row) do
    like = Map.get(row, :like_count, 0)

    """
    <div class="box">
      <a href="/decklist/view/#{id}/slug">Deck #{id}</a>
      <a id="social-icon-like" class="social-icon-like"><span class="num">#{like}</span></a>
      <a id="social-icon-favorite" class="social-icon-favorite"><span class="num">0</span></a>
      <a id="social-icon-comment" class="social-icon-comment"><span class="num">0</span></a>
      <a href="/user/profile/#{user_id}/#{username}" class="username">#{username}</a>
    </div>
    """
  end

  defp pagination_html(:none), do: ""

  defp pagination_html(last_page) do
    """
    <ul class="pagination">
      <li><a href="/decklists/find?sort=date">1</a></li>
      <li><a href="/decklists/find/#{last_page}?sort=date">#{last_page}</a></li>
    </ul>
    """
  end

  defp page_html(rows, opts \\ []) do
    last_page = Keyword.get(opts, :last_page, :none)
    boxes = Enum.map_join(rows, "\n", &box_html/1)

    """
    #{pagination_html(last_page)}
    <div class="decklists">
    #{boxes}
    </div>
    """
  end

  defp stub_page(page, html) do
    Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
      if conn.request_path == "/decklists/find/#{page}" do
        Req.Test.html(conn, html)
      else
        conn |> Plug.Conn.put_status(404) |> Req.Test.html("")
      end
    end)
  end

  defp current_started_at do
    {:ok, state} = Decks.get_mcdb_scrape_state(authorize?: false)
    state.started_at
  end

  describe "chain insert regression" do
    test "the next page is enqueued even while the inserting job is itself executing" do
      stub_page(1, page_html([row(1001)], last_page: 5))

      {:ok, job} = McdbScrape.start()

      from(j in Oban.Job, where: j.id == ^job.id)
      |> Sanctum.Repo.update_all(set: [state: "executing"])

      assert :ok = McdbScrapeWorker.perform(%{job | state: "executing"})

      assert_enqueued(worker: McdbScrapeWorker, args: %{"page" => 2})
    end
  end

  describe "run_page/3 — middle page" do
    test "applies the page, updates the state, and chains the next page" do
      hero = create_hero()
      create_mcdb_deck(hero, "1001")

      stub_page(1, page_html([row(1001, like_count: 7)], last_page: 10))

      {:ok, _job} = McdbScrape.start()
      started_at = current_started_at()

      assert :ok = McdbScrape.run_page(1, :date, started_at)

      deck = Deck |> Ash.Query.filter(mcdb_id == "1001") |> Ash.read_one!(authorize?: false)
      assert deck.mcdb_like_count == 7

      {:ok, user} = Decks.find_or_create_mcdb_user(%{mcdb_user_id: 901_001})
      assert user.username == "user1001"

      {:ok, state} = Decks.get_mcdb_scrape_state(authorize?: false)
      assert state.status == :running
      assert state.page == 1
      assert state.last_page == 10
      assert state.rows_seen == 1
      assert state.matched == 1
      assert state.unmatched == 0
      assert state.users_updated == 1

      assert_enqueued(worker: McdbScrapeWorker, args: %{"page" => 2})
    end
  end

  describe "run_page/3 — last page" do
    test "finishes the sweep and reports missing decklists" do
      hero = create_hero()
      create_mcdb_deck(hero, "2001")
      create_mcdb_deck(hero, "2002")
      create_mcdb_deck(hero, "2003", %{mcdb_type: :deck})

      {:ok, _job} = McdbScrape.start()
      started_at = current_started_at()

      # Imported by the hourly sync mid-sweep — must not count as missing.
      create_mcdb_deck(hero, "2004")

      stub_page(9, page_html([row(2001)], last_page: 9))

      assert :ok = McdbScrape.run_page(9, :date, started_at)

      {:ok, state} = Decks.get_mcdb_scrape_state(authorize?: false)
      assert state.status == :done
      assert state.finished_at != nil
      # Only "2002": "2003" is a :deck (not :decklist), "2004" arrived after
      # the sweep started, and "2001" was just seen/applied on this page.
      assert state.missing_count == 1

      refute_enqueued(worker: McdbScrapeWorker, args: %{"page" => 10})
    end
  end

  describe "run_page/3 — overshoot" do
    test "0 rows with last_page < page finishes without applying" do
      {:ok, _job} = McdbScrape.start(page: 50)
      started_at = current_started_at()

      stub_page(50, page_html([], last_page: 40))

      assert :ok = McdbScrape.run_page(50, :date, started_at)

      {:ok, state} = Decks.get_mcdb_scrape_state(authorize?: false)
      assert state.status == :done

      refute_enqueued(worker: McdbScrapeWorker, args: %{"page" => 51})
    end
  end

  describe "run_page/3 — empty page within range" do
    test "is an error, not a finish, and leaves counters untouched" do
      {:ok, _job} = McdbScrape.start(page: 5)
      started_at = current_started_at()

      stub_page(5, page_html([], last_page: 10))

      assert {:error, {:empty_page, 5, 10}} = McdbScrape.run_page(5, :date, started_at)

      {:ok, state} = Decks.get_mcdb_scrape_state(authorize?: false)
      assert state.status == :running
      assert state.page == 4
      assert state.matched == 0

      refute_enqueued(worker: McdbScrapeWorker, args: %{"page" => 6})
    end
  end

  describe "HTTP failure" do
    test "a 503 fails the job and does not apply or chain anything" do
      Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
        conn |> Plug.Conn.put_status(503) |> Req.Test.html("")
      end)

      {:ok, job} = McdbScrape.start(page: 7)

      assert {:error, _reason} = McdbScrapeWorker.perform(%{job | attempt: 1})

      refute_enqueued(worker: McdbScrapeWorker, args: %{"page" => 8})

      {:ok, state} = Decks.get_mcdb_scrape_state(authorize?: false)
      assert state.status == :running
      assert state.last_error =~ "page 7"
    end

    test "on the final attempt, marks the sweep failed" do
      Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
        conn |> Plug.Conn.put_status(503) |> Req.Test.html("")
      end)

      {:ok, job} = McdbScrape.start(page: 7)
      final_job = %{job | attempt: job.max_attempts}

      assert {:error, _reason} = McdbScrapeWorker.perform(final_job)

      refute_enqueued(worker: McdbScrapeWorker, args: %{"page" => 8})

      {:ok, state} = Decks.get_mcdb_scrape_state(authorize?: false)
      assert state.status == :failed
      assert state.last_error =~ "page 7"
    end
  end

  describe "start/1 — uniqueness" do
    test "a second call while one is already queued/executing returns conflict?: true" do
      {:ok, job1} = McdbScrape.start()
      refute job1.conflict?

      {:ok, job2} = McdbScrape.start()
      assert job2.conflict?
    end
  end

  describe "start/1 — resume" do
    test "keeps counters/started_at and enqueues from the given page" do
      {:ok, job1} = McdbScrape.start()
      started_at = current_started_at()

      # Simulate the original job exhausting its retries (a terminal state, so
      # it no longer blocks a fresh insert via the worker's uniqueness).
      from(j in Oban.Job, where: j.id == ^job1.id)
      |> Sanctum.Repo.update_all(set: [state: "discarded"])

      Decks.put_mcdb_scrape_state!(
        %{
          status: :failed,
          page: 4,
          last_page: 20,
          rows_seen: 40,
          matched: 38,
          unmatched: 2,
          users_updated: 30,
          started_at: started_at,
          last_error: "boom"
        },
        authorize?: false
      )

      {:ok, job2} = McdbScrape.start(page: 5, resume: true)
      refute job2.conflict?
      assert job2.args["page"] == 5

      {:ok, state} = Decks.get_mcdb_scrape_state(authorize?: false)
      assert state.status == :running
      assert state.page == 4
      assert state.rows_seen == 40
      assert state.matched == 38
      assert DateTime.compare(state.started_at, started_at) == :eq
      assert state.last_error == nil
      assert state.missing_count == nil
    end
  end

  describe "backoff/1" do
    test "grows monotonically and caps at an hour" do
      backoffs = for attempt <- 1..12, do: McdbScrapeWorker.backoff(%Oban.Job{attempt: attempt})

      assert backoffs
             |> Enum.chunk_every(2, 1, :discard)
             |> Enum.all?(fn [a, b] -> b >= a end)

      assert Enum.max(backoffs) == 3600
      assert List.last(backoffs) == 3600
    end
  end

  describe "username_coverage/0" do
    test "counts total/filled and decklist-author subsets" do
      hero = create_hero()

      {:ok, alice} = Decks.find_or_create_mcdb_user(%{mcdb_user_id: 11, username: "alice"})
      {:ok, _bob} = Decks.find_or_create_mcdb_user(%{mcdb_user_id: 12, username: "bob"})
      {:ok, carol} = Decks.find_or_create_mcdb_user(%{mcdb_user_id: 13})

      create_mcdb_deck(hero, "9001", %{mcdb_user_id: alice.id})
      # Carol only authored a private :deck-type deck — excluded from the
      # decklist-author pair (she can never appear on a list page).
      create_mcdb_deck(hero, "9002", %{mcdb_user_id: carol.id, mcdb_type: :deck})

      coverage = McdbScrape.username_coverage()

      assert coverage.total == 3
      assert coverage.with_username == 2
      assert coverage.decklist_authors == 1
      assert coverage.decklist_authors_with_username == 1
    end
  end

  describe "state upsert" do
    test "start/1 clears finished_at/missing_count/last_error from a previous completed run" do
      Decks.put_mcdb_scrape_state!(
        %{
          status: :done,
          sort: "date",
          page: 100,
          last_page: 100,
          rows_seen: 1200,
          matched: 1100,
          unmatched: 100,
          users_updated: 900,
          started_at: DateTime.add(DateTime.utc_now(), -3600, :second),
          finished_at: DateTime.utc_now(),
          last_error: "stale error",
          missing_count: 5
        },
        authorize?: false
      )

      {:ok, job} = McdbScrape.start()
      refute job.conflict?

      {:ok, state} = Decks.get_mcdb_scrape_state(authorize?: false)
      assert state.status == :running
      assert state.finished_at == nil
      assert state.missing_count == nil
      assert state.last_error == nil
      assert state.rows_seen == 0
      assert state.matched == 0
    end
  end
end
