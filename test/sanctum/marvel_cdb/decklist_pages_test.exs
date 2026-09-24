defmodule Sanctum.MarvelCdb.DecklistPagesTest do
  @moduledoc false

  # async: false — the tests toggle the global `:marvel_cdb_req_options` env.
  use Sanctum.DataCase, async: false

  import Ecto.Query

  require Ash.Query

  alias Sanctum.Decks.Deck
  alias Sanctum.Decks.McdbUser
  alias Sanctum.MarvelCdb
  alias Sanctum.MarvelCdb.DecklistPages

  setup do
    original = Application.get_env(:sanctum, :marvel_cdb_req_options)

    Application.put_env(:sanctum, :marvel_cdb_req_options,
      plug: {Req.Test, Sanctum.MarvelCdb},
      retry: false
    )

    on_exit(fn -> Application.put_env(:sanctum, :marvel_cdb_req_options, original) end)
    :ok
  end

  defp fixture(name) do
    File.read!(Path.join([__DIR__, "..", "..", "fixtures", "marvel_cdb", "decklist_pages", name]))
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

  # Push updated_at into the past so a spurious bump can't hide inside the
  # same-second cast window of :utc_datetime.
  defp age(deck, timestamp) do
    Sanctum.Repo.update_all(from(d in Deck, where: d.id == ^deck.id),
      set: [updated_at: timestamp]
    )

    Ash.get!(Deck, deck.id, authorize?: false)
  end

  describe "parse/1 — normal page" do
    setup do
      %{html: fixture("page_date_1.html")}
    end

    test "reads 12 rows with integer ids and counts", %{html: html} do
      %{rows: rows, last_page: last_page} = DecklistPages.parse(html)

      assert length(rows) == 12
      assert Enum.all?(rows, &(&1.decklist_id =~ ~r/^\d+$/))
      assert Enum.all?(rows, &is_integer(&1.like_count))
      assert Enum.all?(rows, &is_integer(&1.favorite_count))
      assert Enum.all?(rows, &is_integer(&1.comment_count))

      first = hd(rows)
      assert first.decklist_id == "67151"
      assert first.like_count == 0
      assert first.favorite_count == 0
      assert first.comment_count == 0
      assert first.user_id == 78_392
      assert first.username == "atom"

      # The version badge ("3.0" on the first row) is never mistaken for a count.
      refute Enum.any?(rows, &(&1.like_count == 3 or &1.favorite_count == 3))

      assert last_page == 4560
    end
  end

  describe "parse/1 — last page" do
    setup do
      %{html: fixture("page_last.html")}
    end

    test "row count matches its boxes and last_page is its own page number", %{html: html} do
      %{rows: rows, last_page: last_page} = DecklistPages.parse(html)

      assert length(rows) == 3
      assert last_page == 4560
    end
  end

  describe "parse/1 — no-author row" do
    # Hand-edited copy of page_date_1.html: MarvelCDB's template always
    # renders the author, so a missing author is synthetic — it exercises
    # the "don't borrow the neighboring row's author" guarantee. One other
    # row's username is also swapped for an entity-bearing name.
    setup do
      %{html: fixture("page_no_author.html")}
    end

    test "the row keeps a nil author, and the next row keeps its own", %{html: html} do
      %{rows: rows} = DecklistPages.parse(html)

      assert length(rows) == 12

      no_author = Enum.find(rows, &(&1.decklist_id == "67147"))
      assert no_author.user_id == nil
      assert no_author.username == nil

      neighbor = Enum.find(rows, &(&1.decklist_id == "67146"))
      assert neighbor.user_id == 78_538
      assert neighbor.username == "Tom & Jerry's"
    end
  end

  describe "parse/1 — out-of-range page" do
    test "returns no rows and last_page from link text, not hrefs" do
      html = """
      <div class="decklists"></div>
      <ul class="pagination pagination-sm" style="margin: 0;">
        <li class=""><a href="/decklists/find/99998?sort=date">&laquo;</a></li>
        <li><a href="/decklists/find?sort=date">1</a></li>
        <li><a href="/decklists/find/4560?sort=date">4560</a></li>
        <li class=""><a href="/decklists/find/4560?sort=date">&raquo;</a></li>
      </ul>
      """

      assert DecklistPages.parse(html) == %{rows: [], last_page: 4560}
    end
  end

  describe "fetch/2" do
    test "requests the right path/query/user-agent and parses the html" do
      fixture_html = fixture("page_last.html")

      Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
        assert conn.request_path == "/decklists/find/3"
        assert conn.query_string == "sort=likes"
        assert Plug.Conn.get_req_header(conn, "user-agent") == [MarvelCdb.user_agent()]
        assert MarvelCdb.user_agent() =~ "jwstover@gmail.com"
        assert MarvelCdb.user_agent() =~ "Sanctum/"

        Req.Test.html(conn, fixture_html)
      end)

      assert {:ok, %{rows: rows, last_page: 4560}} = DecklistPages.fetch(3, :likes)
      assert length(rows) == 3
    end

    test "returns an error for a non-200 response" do
      Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.html("")
      end)

      assert {:error, _reason} = DecklistPages.fetch(3, :date)
    end
  end

  describe "apply_rows/2" do
    test "updates matched decks and fills usernames, leaves others untouched" do
      hero = create_hero()
      aged_at = ~U[2023-06-01 12:00:00Z]

      matched_atom = create_mcdb_deck(hero, "67151") |> age(aged_at)
      matched_bluer = create_mcdb_deck(hero, "67147") |> age(aged_at)

      # Same id, different id space — must stay untouched by a decklist scrape.
      other_space = create_mcdb_deck(hero, "67151", %{mcdb_type: :deck})

      # An unmatched row's decklist id — no deck locally, so it must not be created.
      unmatched_id = "999999999"

      McdbUser
      |> Ash.Changeset.for_create(:create, %{mcdb_user_id: 19_660})
      |> Ash.create!(authorize?: false)

      rows = [
        %{
          decklist_id: "67151",
          like_count: 5,
          favorite_count: 2,
          comment_count: 1,
          user_id: 78_392,
          username: "atom"
        },
        %{
          decklist_id: "67147",
          like_count: 3,
          favorite_count: 0,
          comment_count: 0,
          user_id: 19_660,
          username: "BlueRiver"
        },
        %{
          decklist_id: unmatched_id,
          like_count: 9,
          favorite_count: 9,
          comment_count: 9,
          user_id: 1,
          username: "nobody"
        },
        # A no-author row must not blank an existing username or crash.
        %{
          decklist_id: "67147",
          like_count: 0,
          favorite_count: 0,
          comment_count: 0,
          user_id: nil,
          username: nil
        }
      ]

      summary = DecklistPages.apply_rows(rows)

      assert summary == %{matched: 3, unmatched: 1, updated_users: 2}

      matched_atom = Ash.get!(Deck, matched_atom.id, authorize?: false)
      assert matched_atom.mcdb_like_count == 5
      assert matched_atom.mcdb_social_synced_at != nil
      assert DateTime.compare(matched_atom.updated_at, aged_at) == :eq

      matched_bluer = Ash.get!(Deck, matched_bluer.id, authorize?: false)
      assert matched_bluer.mcdb_like_count == 0
      assert DateTime.compare(matched_bluer.updated_at, aged_at) == :eq

      other_space = Ash.get!(Deck, other_space.id, authorize?: false)
      assert other_space.mcdb_like_count == 0
      assert other_space.mcdb_social_synced_at == nil

      refute Ash.exists?(Deck |> Ash.Query.filter(mcdb_id == ^unmatched_id))

      {:ok, atom_user} = Sanctum.Decks.find_or_create_mcdb_user(%{mcdb_user_id: 78_392})
      assert atom_user.username == "atom"

      {:ok, bluer_user} = Sanctum.Decks.find_or_create_mcdb_user(%{mcdb_user_id: 19_660})
      assert bluer_user.username == "BlueRiver"
    end
  end

  describe "upsert-clobber regression" do
    test "re-importing a deck preserves mcdb_like_count and mcdb_social_synced_at" do
      hero_card = create(Sanctum.Games.Card, attrs: %{base_code: "77001", code: "77001"})

      create(Sanctum.Games.CardSide,
        attrs: %{
          card_id: hero_card.id,
          name: "Regression Hero",
          type: :hero,
          code: "77001a",
          side_identifier: "A",
          is_primary_side: true
        }
      )

      create(Sanctum.Games.CardSide,
        attrs: %{
          card_id: hero_card.id,
          name: "Regression Alter Ego",
          type: :alter_ego,
          code: "77001b",
          side_identifier: "B",
          is_primary_side: false
        }
      )

      slot_card = create(Sanctum.Games.Card, attrs: %{base_code: "77002", code: "77002"})

      create(Sanctum.Games.CardSide,
        attrs: %{card_id: slot_card.id, code: "77002", side_identifier: "A"}
      )

      payload = %{
        "id" => 55_555,
        "name" => "Regression deck",
        "hero_code" => "77001a",
        "slots" => %{"77002" => 2}
      }

      assert {:ok, deck} = MarvelCdb.import_decklist(payload)

      synced_at = DateTime.utc_now() |> DateTime.truncate(:second)

      deck =
        Sanctum.Decks.set_deck_mcdb_social!(
          deck,
          %{mcdb_like_count: 42, mcdb_social_synced_at: synced_at},
          authorize?: false
        )

      assert deck.mcdb_like_count == 42

      # Re-import the same decklist — must not clobber the scraped social data.
      assert {:ok, reimported} = MarvelCdb.import_decklist(payload)
      assert reimported.id == deck.id
      assert reimported.mcdb_like_count == 42
      assert reimported.mcdb_social_synced_at == synced_at
    end

    test "find_or_create_mcdb_user preserves an existing username" do
      {:ok, user} =
        Sanctum.Decks.find_or_create_mcdb_user(%{mcdb_user_id: 909_090, username: "original"})

      assert user.username == "original"

      {:ok, refetched} = Sanctum.Decks.find_or_create_mcdb_user(%{mcdb_user_id: 909_090})
      assert refetched.id == user.id
      assert refetched.username == "original"
    end
  end
end
