defmodule Sanctum.Decks.McdbDeckRefreshTest do
  @moduledoc false

  # async: false — toggles the global `:marvel_cdb_req_options` env and
  # inserts real `oban_jobs` rows.
  use Sanctum.DataCase, async: false
  use Oban.Testing, repo: Sanctum.Repo

  import Ecto.Query

  alias Sanctum.Decks.Deck
  alias Sanctum.Decks.McdbDeckRefresh
  alias Sanctum.Decks.McdbDeckRefreshWorker
  alias Sanctum.Repo

  @config [floor_days: 3, ceiling_days: 365, growth_factor: 2.0, initial_delay_days: 7]
  @day 86_400

  setup do
    original = Application.get_env(:sanctum, :marvel_cdb_req_options)
    original_pace = Application.get_env(:sanctum, Sanctum.Decks.McdbScrapeWorker)

    Application.put_env(:sanctum, :marvel_cdb_req_options,
      plug: {Req.Test, Sanctum.MarvelCdb},
      retry: false
    )

    Application.put_env(:sanctum, Sanctum.Decks.McdbScrapeWorker, pace_seconds: 0..0)

    on_exit(fn ->
      Application.put_env(:sanctum, :marvel_cdb_req_options, original)

      if original_pace do
        Application.put_env(:sanctum, Sanctum.Decks.McdbScrapeWorker, original_pace)
      else
        Application.delete_env(:sanctum, Sanctum.Decks.McdbScrapeWorker)
      end
    end)

    {:ok, hero: create_hero(), now: DateTime.truncate(DateTime.utc_now(), :second)}
  end

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

  defp create_deck(hero, mcdb_id, type \\ :decklist) do
    Deck
    |> Ash.Changeset.for_create(:create, %{
      title: "Deck #{mcdb_id}",
      hero_id: hero.id,
      source: :marvelcdb,
      mcdb_id: mcdb_id,
      mcdb_type: type
    })
    |> Ash.create!(authorize?: false)
  end

  # Writes columns with update_all so `updated_at` isn't bumped.
  defp set_cols!(deck, cols) do
    from(d in Deck, where: d.id == ^deck.id) |> Repo.update_all(set: cols)
    reload(deck)
  end

  defp reload(deck), do: Ash.get!(Deck, deck.id, authorize?: false)

  defp ago(now, days), do: DateTime.add(now, -days * @day, :second)
  defp ahead(now, days), do: DateTime.add(now, days * @day, :second)

  # A due deck (next_check_at in the past); `changed_at` defaults to 10 days ago.
  defp due_deck(hero, mcdb_id, now, opts \\ []) do
    hero
    |> create_deck(mcdb_id)
    |> set_cols!(
      mcdb_like_changed_at: Keyword.get(opts, :changed_at, ago(now, 10)),
      mcdb_social_next_check_at: Keyword.get(opts, :due, ago(now, 1))
    )
  end

  defp detail_html(likes) do
    """
    <span class="social-icons">
      <a id="social-icon-like" href="#" class="social-icon-like" title="Like">
        <span class="fa fa-heart"></span> <span class="num">#{likes}</span>
      </a>
      <a id="social-icon-favorite" href="#" class="social-icon-favorite" title="Favorite">
        <span class="fa fa-star"></span> <span class="num">0</span>
      </a>
      <a id="social-icon-comment" href="#comment-form" class="social-icon-comment" title="Comment">
        <span class="fa fa-comment"></span> <span class="num">0</span>
      </a>
    </span>
    """
  end

  # `responses` maps mcdb_id => integer likes | :not_found | :no_counts | :error.
  defp stub_details(responses) do
    test_pid = self()

    Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
      "/decklist/view/" <> id = conn.request_path
      send(test_pid, {:mcdb_detail, id})

      case Map.fetch!(responses, id) do
        :not_found -> Plug.Conn.send_resp(conn, 404, "")
        :error -> Plug.Conn.send_resp(conn, 500, "")
        :no_counts -> Req.Test.html(conn, "<html><body>changed layout</body></html>")
        likes -> Req.Test.html(conn, detail_html(likes))
      end
    end)
  end

  defp run(opts \\ []) do
    McdbDeckRefresh.run(
      Keyword.merge([pace_fun: fn -> :ok end, backfill_running_fun: fn -> false end], opts)
    )
  end

  defp requested_ids do
    Stream.repeatedly(fn ->
      receive do
        {:mcdb_detail, id} -> id
      after
        0 -> nil
      end
    end)
    |> Enum.take_while(& &1)
  end

  describe "next_check_at/3" do
    test "floors the interval when the count just changed", %{now: now} do
      assert McdbDeckRefresh.next_check_at(now, now, @config) == ahead(now, 3)
    end

    test "grows with how long the deck has been quiet", %{now: now} do
      assert McdbDeckRefresh.next_check_at(now, ago(now, 10), @config) == ahead(now, 20)
    end

    test "caps at the ceiling", %{now: now} do
      assert McdbDeckRefresh.next_check_at(now, ago(now, 730), @config) == ahead(now, 365)
    end
  end

  describe "seeding" do
    test "schedules new, old, and leaves native and already-scheduled decks alone", %{
      hero: hero,
      now: now
    } do
      created = ago(now, 1)
      new_deck = hero |> create_deck("1") |> set_cols!(mcdb_date_creation: created)
      old_created = ago(now, 500)
      old_deck = hero |> create_deck("2") |> set_cols!(mcdb_date_creation: old_created)
      native = create_deck(hero, "3", :deck)
      scheduled_at = ahead(now, 5)
      scheduled = hero |> create_deck("4") |> set_cols!(mcdb_social_next_check_at: scheduled_at)
      updated_before = Enum.map([new_deck, old_deck, native, scheduled], & &1.updated_at)

      stub_details(%{})
      assert {:ok, %{due: 0}} = run()

      new_deck = reload(new_deck)
      assert DateTime.compare(new_deck.mcdb_social_next_check_at, ahead(created, 7)) == :eq
      assert DateTime.compare(new_deck.mcdb_like_changed_at, created) == :eq

      old_deck = reload(old_deck)
      assert DateTime.compare(old_deck.mcdb_social_next_check_at, now) in [:gt, :eq]
      assert DateTime.compare(old_deck.mcdb_social_next_check_at, ahead(now, 366)) == :lt
      assert DateTime.compare(old_deck.mcdb_like_changed_at, old_created) == :eq

      native = reload(native)
      assert native.mcdb_social_next_check_at == nil
      assert native.mcdb_like_changed_at == nil

      assert DateTime.compare(reload(scheduled).mcdb_social_next_check_at, scheduled_at) == :eq

      updated_after = Enum.map([new_deck, old_deck, native, reload(scheduled)], & &1.updated_at)
      assert updated_before == updated_after
    end
  end

  describe "run/1" do
    test "changed count: stores it, stamps changed_at, and schedules at the floor", %{
      hero: hero,
      now: now
    } do
      deck = due_deck(hero, "10", now)
      stub_details(%{"10" => 5})

      assert {:ok, %{checked: 1, changed: 1}} = run(now: now)

      deck2 = reload(deck)
      assert deck2.mcdb_like_count == 5
      assert DateTime.compare(deck2.mcdb_like_changed_at, now) == :eq
      assert DateTime.compare(deck2.mcdb_social_next_check_at, ahead(now, 3)) == :eq
      assert DateTime.compare(deck2.mcdb_social_synced_at, now) == :eq
      assert DateTime.compare(deck2.updated_at, deck.updated_at) == :eq
    end

    test "unchanged count: keeps changed_at and backs off", %{hero: hero, now: now} do
      changed_at = ago(now, 10)
      deck = due_deck(hero, "11", now, changed_at: changed_at)
      stub_details(%{"11" => 0})

      assert {:ok, %{checked: 1, changed: 0}} = run(now: now)

      deck = reload(deck)
      assert deck.mcdb_like_count == 0
      assert DateTime.compare(deck.mcdb_like_changed_at, changed_at) == :eq
      assert DateTime.compare(deck.mcdb_social_next_check_at, ahead(now, 20)) == :eq
    end

    test "404: leaves counts, pushes to the ceiling, and continues", %{hero: hero, now: now} do
      gone = due_deck(hero, "12", now)
      ok = due_deck(hero, "13", now, due: ago(now, 0))
      stub_details(%{"12" => :not_found, "13" => 2})

      assert {:ok, %{not_found: 1, checked: 1}} = run(now: now)

      gone = reload(gone)
      assert gone.mcdb_like_count == 0
      assert gone.mcdb_social_synced_at == nil
      assert DateTime.compare(gone.mcdb_social_next_check_at, ahead(now, 365)) == :eq
      assert reload(ok).mcdb_like_count == 2
    end

    test "a parse failure defers by the floor without touching counts", %{hero: hero, now: now} do
      bad = due_deck(hero, "14", now)
      stub_details(%{"14" => :no_counts})

      assert {:ok, %{parse_failures: 1, checked: 0}} = run(now: now)

      bad = reload(bad)
      assert bad.mcdb_like_count == 0
      assert DateTime.compare(bad.mcdb_social_next_check_at, ahead(now, 3)) == :eq
    end

    test "three parse failures halt the run", %{hero: hero, now: now} do
      for id <- ~w(15 16 17), do: due_deck(hero, id, now)
      stub_details(%{"15" => :no_counts, "16" => :no_counts, "17" => :no_counts})

      assert run(now: now) == {:error, {:parse_failures, 3}}
    end

    test "a 5xx halts, leaves that deck's schedule untouched, keeps earlier decks", %{
      hero: hero,
      now: now
    } do
      first = due_deck(hero, "18", now, due: ago(now, 3))
      failing_due = ago(now, 2)
      failing = due_deck(hero, "19", now, due: failing_due)
      third = due_deck(hero, "20", now, due: ago(now, 1))
      stub_details(%{"18" => 4, "19" => :error, "20" => 1})

      assert {:error, {"19", _}} = run(now: now)

      assert reload(first).mcdb_like_count == 4
      assert DateTime.compare(reload(failing).mcdb_social_next_check_at, failing_due) == :eq
      assert DateTime.compare(reload(third).mcdb_social_next_check_at, ago(now, 1)) == :eq
      assert requested_ids() == ["18", "19"]
    end

    test "caps the batch, oldest-due first, and never requests decks not yet due", %{
      hero: hero,
      now: now
    } do
      for {id, days} <- [{"21", 5}, {"22", 4}, {"23", 3}, {"24", 2}, {"25", 1}] do
        due_deck(hero, id, now, due: ago(now, days))
      end

      future = due_deck(hero, "26", now, due: ahead(now, 2))
      stub_details(Map.new(~w(21 22 23 24 25 26), &{&1, 0}))

      assert {:ok, %{due: 5, checked: 3, backlog: 2}} = run(now: now, batch_size: 3)

      assert requested_ids() == ["21", "22", "23"]
      assert DateTime.compare(reload(future).mcdb_social_next_check_at, ahead(now, 2)) == :eq
    end

    test "skips when the backfill is running", %{hero: hero, now: now} do
      due_deck(hero, "30", now)
      stub_details(%{})

      assert run(backfill_running_fun: fn -> true end) == {:skipped, :backfill_running}
      assert requested_ids() == []
    end

    test "skips while the social refresh is executing", %{hero: hero, now: now} do
      due_deck(hero, "31", now)
      stub_details(%{})

      %Oban.Job{}
      |> Ecto.Changeset.change(
        worker: "Sanctum.Decks.McdbSocialRefreshWorker",
        queue: "mcdb_scrape",
        state: "executing",
        args: %{}
      )
      |> Repo.insert!()

      assert run() == {:skipped, :social_refresh_running}
      assert requested_ids() == []
    end
  end

  test "the worker returns :ok and is on the crontab", %{hero: hero, now: now} do
    due_deck(hero, "40", now)
    stub_details(%{"40" => 1})

    assert :ok = perform_job(McdbDeckRefreshWorker, %{})

    crontab =
      Application.fetch_env!(:sanctum, Oban)[:plugins]
      |> Enum.find_value(fn
        {Oban.Plugins.Cron, opts} -> opts[:crontab]
        _ -> nil
      end)

    assert Enum.any?(crontab, fn {_expr, worker} -> worker == McdbDeckRefreshWorker end)
  end
end
