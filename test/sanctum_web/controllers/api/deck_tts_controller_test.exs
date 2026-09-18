defmodule SanctumWeb.Api.DeckTTSControllerTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Sanctum.Factory

  defp make_deck(attrs \\ %{}) do
    hero_card =
      create(Sanctum.Games.Card, attrs: %{base_code: "90050", code: "90050a", set: "spider_man"})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: hero_card.id,
        name: "Spider-Man",
        type: :hero,
        ownership: :hero,
        code: "90050a",
        side_identifier: "A",
        is_primary_side: true
      }
    )

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: hero_card.id,
        name: "Peter Parker",
        type: :alter_ego,
        code: "90050b",
        side_identifier: "B",
        is_primary_side: false
      }
    )

    {:ok, hero} =
      Sanctum.Heroes.find_or_create_hero(%{
        hero_name: "Spider-Man",
        alter_ego_name: "Peter Parker",
        set: "spider_man",
        base_code: "90050",
        card_id: hero_card.id
      })

    default_attrs = %{
      title: "Web Warrior",
      hero_id: hero.id,
      aspects: [:justice],
      source: :native,
      visibility: :published,
      state: :final
    }

    {:ok, deck} =
      Sanctum.Decks.Deck
      |> Ash.Changeset.for_create(:create, Map.merge(default_attrs, attrs))
      |> Ash.create(authorize?: false)

    # Dropped silently: a hero-owned card arrives via the hero kit bag, not
    # a per-card lookup.
    Sanctum.Decks.DeckCard
    |> Ash.Changeset.for_create(:create, %{deck_id: deck.id, card_id: hero_card.id, quantity: 1})
    |> Ash.create!(authorize?: false)

    ally = create(Sanctum.Games.Card, attrs: %{base_code: "90051", code: "90051a"})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: ally.id,
        name: "Beat Cop",
        type: :ally,
        ownership: :player,
        aspect: "justice",
        cost: 3,
        code: "90051a",
        side_identifier: "A",
        is_primary_side: true
      }
    )

    Sanctum.Decks.DeckCard
    |> Ash.Changeset.for_create(:create, %{deck_id: deck.id, card_id: ally.id, quantity: 2})
    |> Ash.create!(authorize?: false)

    # An encounter card has no pool bag, so it lands in `unmapped`.
    encounter_card = create(Sanctum.Games.Card, attrs: %{base_code: "90052", code: "90052a"})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: encounter_card.id,
        name: "Sandman",
        type: :villain,
        ownership: :encounter,
        code: "90052a",
        side_identifier: "A",
        is_primary_side: true
      }
    )

    Sanctum.Decks.DeckCard
    |> Ash.Changeset.for_create(:create, %{
      deck_id: deck.id,
      card_id: encounter_card.id,
      quantity: 1
    })
    |> Ash.create!(authorize?: false)

    deck
  end

  describe "GET /api/decks/:id/tts" do
    test "a published deck returns the names-only payload", %{conn: conn} do
      deck = make_deck()

      conn =
        conn
        |> put_req_header("fly-client-ip", "203.0.113.1")
        |> get(~p"/api/decks/#{deck.id}/tts")

      assert %{
               "version" => 1,
               "deck" => %{"id" => id, "title" => "Web Warrior", "aspects" => ["justice"]},
               "hero" => %{
                 "identity" => "Spider-Man",
                 "kit" => "Spider-Man Cards",
                 "hp_counter" => "Spider-Man's HP Counter"
               },
               "side_decks" => [],
               "cards" => [
                 %{
                   "pool" => "JusticeCards",
                   "name" => "Beat Cop",
                   "subname" => nil,
                   "quantity" => 2
                 }
               ],
               "unmapped" => ["Sandman"]
             } = json_response(conn, 200)

      assert id == deck.id
    end

    test "the 200 response carries no content-security-policy header", %{conn: conn} do
      deck = make_deck()

      conn =
        conn
        |> put_req_header("fly-client-ip", "203.0.113.2")
        |> get(~p"/api/decks/#{deck.id}/tts")

      assert conn.status == 200
      assert get_resp_header(conn, "content-security-policy") == []
    end

    test "a private deck is 404 to an anonymous visitor", %{conn: conn} do
      deck = make_deck(%{visibility: :private, state: :draft})

      conn =
        conn
        |> put_req_header("fly-client-ip", "203.0.113.3")
        |> get(~p"/api/decks/#{deck.id}/tts")

      assert json_response(conn, 404)
    end

    test "a private deck is 200 for its owner via bearer token", %{conn: conn} do
      owner = user_fixture()
      deck = make_deck(%{visibility: :private, state: :draft, owner_id: owner.id})
      {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(owner)

      conn =
        conn
        |> put_req_header("fly-client-ip", "203.0.113.4")
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/decks/#{deck.id}/tts")

      assert %{"deck" => %{"id" => id}} = json_response(conn, 200)
      assert id == deck.id
    end

    test "an unknown uuid is 404", %{conn: conn} do
      conn =
        conn
        |> put_req_header("fly-client-ip", "203.0.113.5")
        |> get(~p"/api/decks/#{Ash.UUID.generate()}/tts")

      assert json_response(conn, 404)
    end

    test "a malformed id is 404, not a 500", %{conn: conn} do
      conn =
        conn
        |> put_req_header("fly-client-ip", "203.0.113.6")
        |> get("/api/decks/not-a-uuid/tts")

      assert json_response(conn, 404)
    end

    test "the 31st request in a minute from one IP is rate limited", %{conn: _conn} do
      deck = make_deck()
      ip = "203.0.113.77"

      for _ <- 1..30 do
        resp =
          build_conn()
          |> put_req_header("fly-client-ip", ip)
          |> get(~p"/api/decks/#{deck.id}/tts")

        assert resp.status == 200
      end

      resp =
        build_conn()
        |> put_req_header("fly-client-ip", ip)
        |> get(~p"/api/decks/#{deck.id}/tts")

      assert json_response(resp, 429)
    end
  end
end
