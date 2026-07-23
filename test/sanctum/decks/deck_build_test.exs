defmodule Sanctum.Decks.DeckBuildTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  import Sanctum.AccountsFixtures

  alias Sanctum.Decks
  alias Sanctum.Decks.Deck
  alias Sanctum.Decks.DeckCard

  require Ash.Query

  # A hero plus a small signature set: two hero-ownership player cards (one at
  # deck_limit 2), the identity card, and an encounter-ownership obligation
  # that must never be seeded into decks.
  defp make_hero(set) do
    hero_card = create(Sanctum.Games.Card, attrs: %{base_code: "#{set}a", set: set})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: hero_card.id,
        name: "Hero #{set}",
        type: :hero,
        ownership: :hero,
        code: "#{hero_card.code}a",
        side_identifier: "A",
        is_primary_side: true
      }
    )

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: hero_card.id,
        name: "Alter Ego #{set}",
        type: :alter_ego,
        ownership: :hero,
        code: "#{hero_card.code}b",
        side_identifier: "B",
        is_primary_side: false
      }
    )

    signature_double = create(Sanctum.Games.Card, attrs: %{set: set, deck_limit: 2})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: signature_double.id,
        name: "Signature Event #{set}",
        type: :event,
        ownership: :hero,
        code: signature_double.code,
        side_identifier: "A",
        is_primary_side: true
      }
    )

    signature_single = create(Sanctum.Games.Card, attrs: %{set: set, deck_limit: 1, unique: true})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: signature_single.id,
        name: "Signature Ally #{set}",
        type: :ally,
        ownership: :hero,
        code: signature_single.code,
        side_identifier: "A",
        is_primary_side: true
      }
    )

    obligation = create(Sanctum.Games.Card, attrs: %{set: set, deck_limit: 1})

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: obligation.id,
        name: "Obligation #{set}",
        type: :treachery,
        ownership: :encounter,
        code: obligation.code,
        side_identifier: "A",
        is_primary_side: true
      }
    )

    {:ok, hero} =
      Sanctum.Heroes.find_or_create_hero(%{
        hero_name: "Hero #{set}",
        alter_ego_name: "Alter Ego #{set}",
        set: set,
        base_code: hero_card.base_code,
        card_id: hero_card.id
      })

    %{
      hero: hero,
      hero_card: hero_card,
      signature_double: signature_double,
      signature_single: signature_single,
      obligation: obligation
    }
  end

  defp deck_card_rows(deck_id) do
    DeckCard
    |> Ash.Query.filter(deck_id == ^deck_id)
    |> Ash.read!(authorize?: false)
  end

  describe ":build" do
    test "seeds the hero signature set at deck_limit quantities for the actor" do
      %{hero: hero, signature_double: dbl, signature_single: sgl} = make_hero("build_hero_a")
      user = user_fixture()

      deck = Decks.build_deck!(%{hero_id: hero.id, aspects: [:justice]}, actor: user)

      assert deck.owner_id == user.id
      assert deck.source == :native
      assert deck.aspects == [:justice]

      assert deck.title == "Hero build_hero_a · Alter Ego build_hero_a Deck" or
               deck.title =~ "Deck"

      rows = deck_card_rows(deck.id)
      quantities = Map.new(rows, &{&1.card_id, &1.quantity})

      assert quantities[dbl.id] == 2
      assert quantities[sgl.id] == 1
      assert map_size(quantities) == 2
    end

    test "never seeds the identity card or encounter-ownership set cards" do
      %{hero: hero, hero_card: hero_card, obligation: obligation} = make_hero("build_hero_b")
      user = user_fixture()

      deck = Decks.build_deck!(%{hero_id: hero.id}, actor: user)

      card_ids = deck_card_rows(deck.id) |> Enum.map(& &1.card_id)
      refute hero_card.id in card_ids
      refute obligation.id in card_ids
    end

    test "defaults a blank title from the hero display name" do
      %{hero: hero} = make_hero("build_hero_c")
      user = user_fixture()

      deck = Decks.build_deck!(%{hero_id: hero.id}, actor: user)

      assert is_binary(deck.title)
      assert deck.title =~ "Deck"
      assert deck.title =~ "build_hero_c"
    end

    test "keeps an explicit title" do
      %{hero: hero} = make_hero("build_hero_d")
      user = user_fixture()

      deck = Decks.build_deck!(%{hero_id: hero.id, title: "Web Warriors"}, actor: user)

      assert deck.title == "Web Warriors"
    end

    test "is rejected without an actor" do
      %{hero: hero} = make_hero("build_hero_e")

      # relate_actor(:owner) rejects the nil actor before the policy layer
      # gets a say, so this surfaces as Invalid rather than Forbidden. Either
      # way: no deck.
      assert {:error, error} = Decks.build_deck(%{hero_id: hero.id})
      assert error.__struct__ in [Ash.Error.Invalid, Ash.Error.Forbidden]
    end
  end

  describe "set_card_quantity/4" do
    setup do
      %{hero: hero} = make_hero("build_qty")
      user = user_fixture()
      deck = Decks.build_deck!(%{hero_id: hero.id}, actor: user)
      card = create(Sanctum.Games.Card)

      %{user: user, deck: deck, card: card}
    end

    test "inserts, updates in place, and removes at zero", %{user: user, deck: deck, card: card} do
      Decks.set_card_quantity(deck.id, card.id, 1, user)

      assert [%{quantity: 1}] =
               deck_card_rows(deck.id) |> Enum.filter(&(&1.card_id == card.id))

      Decks.set_card_quantity(deck.id, card.id, 3, user)

      assert [%{quantity: 3}] =
               deck_card_rows(deck.id) |> Enum.filter(&(&1.card_id == card.id))

      assert :removed = Decks.set_card_quantity(deck.id, card.id, 0, user)
      assert [] = deck_card_rows(deck.id) |> Enum.filter(&(&1.card_id == card.id))
    end

    test "zero on an absent row is a no-op", %{user: user, deck: deck, card: card} do
      assert :removed = Decks.set_card_quantity(deck.id, card.id, 0, user)
    end

    test "non-owners are forbidden", %{deck: deck, card: card} do
      other = user_fixture()

      assert_raise Ash.Error.Forbidden, fn ->
        Decks.set_card_quantity(deck.id, card.id, 1, other)
      end
    end

    test "anonymous writers are forbidden", %{deck: deck, card: card} do
      assert_raise Ash.Error.Forbidden, fn ->
        Decks.set_card_quantity(deck.id, card.id, 1, nil)
      end
    end
  end

  describe "deck update/destroy policies" do
    setup do
      %{hero: hero} = make_hero("build_policy")
      owner = user_fixture()
      deck = Decks.build_deck!(%{hero_id: hero.id}, actor: owner)

      %{owner: owner, deck: deck}
    end

    test "owner can rename, set aspects, set description, and destroy", %{
      owner: owner,
      deck: deck
    } do
      assert %{title: "Renamed"} = Decks.rename_deck!(deck, %{title: "Renamed"}, actor: owner)

      assert %{aspects: [:pool]} =
               Decks.set_deck_aspects!(deck, %{aspects: [:pool]}, actor: owner)

      assert %{description_md: "**Bold** plan."} =
               Decks.set_deck_description!(deck, %{description_md: "**Bold** plan."},
                 actor: owner
               )

      assert :ok = Decks.destroy_deck!(deck, actor: owner)
    end

    test "non-owner cannot set the description", %{deck: deck} do
      other = user_fixture()

      assert_raise Ash.Error.Forbidden, fn ->
        Decks.set_deck_description!(deck, %{description_md: "graffiti"}, actor: other)
      end
    end

    test "non-owner cannot rename or destroy", %{deck: deck} do
      other = user_fixture()

      assert_raise Ash.Error.Forbidden, fn ->
        Decks.rename_deck!(deck, %{title: "Hijacked"}, actor: other)
      end

      assert_raise Ash.Error.Forbidden, fn ->
        Decks.destroy_deck!(deck, actor: other)
      end
    end

    test "admin bypasses ownership", %{deck: deck} do
      admin = admin_user_fixture()

      assert %{title: "Moderated"} =
               Decks.rename_deck!(deck, %{title: "Moderated"}, actor: admin)
    end

    test "anonymous reads see published decks but not private drafts", %{
      owner: owner,
      deck: deck
    } do
      # Fresh builds are private drafts — invisible to anonymous readers.
      assert {:error, %Ash.Error.Invalid{}} = Decks.get_deck(deck.id)

      deck = Decks.finalize_deck!(deck, actor: owner)
      deck = Decks.publish_deck!(deck, actor: owner)

      assert {:ok, fetched} = Decks.get_deck(deck.id)
      assert fetched.id == deck.id
      assert deck_card_rows(deck.id) != []
    end
  end

  describe "deck lifecycle (draft → finalize → publish)" do
    setup do
      %{hero: hero} = make_hero("build_lifecycle")
      owner = user_fixture()
      deck = Decks.build_deck!(%{hero_id: hero.id}, actor: owner)

      %{owner: owner, deck: deck}
    end

    test "builds start as a private draft", %{deck: deck} do
      assert deck.visibility == :private
      assert deck.state == :draft
    end

    test "finalize then publish", %{owner: owner, deck: deck} do
      deck = Decks.finalize_deck!(deck, actor: owner)
      assert deck.state == :final
      assert deck.visibility == :private

      deck = Decks.publish_deck!(deck, actor: owner)
      assert deck.visibility == :published
    end

    test "a draft cannot be published", %{owner: owner, deck: deck} do
      assert {:error, %Ash.Error.Invalid{}} = Decks.publish_deck(deck, actor: owner)
    end

    test "reopening a published deck withdraws it", %{owner: owner, deck: deck} do
      deck = Decks.finalize_deck!(deck, actor: owner)
      deck = Decks.publish_deck!(deck, actor: owner)

      deck = Decks.reopen_deck!(deck, actor: owner)
      assert deck.state == :draft
      assert deck.visibility == :private
    end

    test "unpublish keeps the deck final but private", %{owner: owner, deck: deck} do
      deck = Decks.finalize_deck!(deck, actor: owner)
      deck = Decks.publish_deck!(deck, actor: owner)

      deck = Decks.unpublish_deck!(deck, actor: owner)
      assert deck.state == :final
      assert deck.visibility == :private
    end

    test "non-owners cannot drive the lifecycle", %{owner: owner, deck: deck} do
      other = user_fixture()

      assert_raise Ash.Error.Forbidden, fn -> Decks.finalize_deck!(deck, actor: other) end

      deck = Decks.finalize_deck!(deck, actor: owner)
      assert_raise Ash.Error.Forbidden, fn -> Decks.publish_deck!(deck, actor: other) end
    end

    test ":browse silently drops others' private decks", %{owner: owner, deck: deck} do
      other = user_fixture()

      browse_ids = fn actor ->
        Deck
        |> Ash.Query.for_read(:browse, %{}, actor: actor)
        |> Ash.read!()
        |> Enum.map(& &1.id)
      end

      admin = admin_user_fixture()

      assert deck.id in browse_ids.(owner)
      refute deck.id in browse_ids.(other)
      refute deck.id in browse_ids.(nil)
      refute deck.id in browse_ids.(admin)

      deck = Decks.finalize_deck!(deck, actor: owner)
      deck = Decks.publish_deck!(deck, actor: owner)

      assert deck.id in browse_ids.(other)
      assert deck.id in browse_ids.(nil)
      assert deck.id in browse_ids.(admin)
    end

    test "private decks are visible to their owner but filtered for others", %{
      owner: owner,
      deck: deck
    } do
      other = user_fixture()

      assert {:ok, _} = Decks.get_deck(deck.id, actor: owner)
      assert {:error, %Ash.Error.Invalid{}} = Decks.get_deck(deck.id, actor: other)
      assert {:error, %Ash.Error.Invalid{}} = Decks.get_deck(deck.id)

      # The admin bypass covers moderation writes only — reads go through the
      # same visibility policy as everyone else.
      admin = admin_user_fixture()
      assert {:error, %Ash.Error.Invalid{}} = Decks.get_deck(deck.id, actor: admin)
    end
  end

  describe ":browse mine:true query" do
    test "returns only the actor's decks" do
      %{hero: hero} = make_hero("build_mine")
      me = user_fixture()
      other = user_fixture()

      mine = Decks.build_deck!(%{hero_id: hero.id}, actor: me)
      _theirs = Decks.build_deck!(%{hero_id: hero.id}, actor: other)

      results =
        Deck
        |> Ash.Query.for_read(:browse, %{query: "mine:true"}, actor: me)
        |> Ash.read!()

      assert Enum.map(results, & &1.id) == [mine.id]
    end

    test "matches nothing without an actor" do
      %{hero: hero} = make_hero("build_mine_anon")
      user = user_fixture()
      _deck = Decks.build_deck!(%{hero_id: hero.id}, actor: user)

      assert Deck |> Ash.Query.for_read(:browse, %{query: "mine:true"}) |> Ash.read!() == []
    end
  end

  test "actorless create_with_cards import path still works" do
    %{hero: hero} = make_hero("build_import")
    cards = create(Sanctum.Games.Card, count: 2)
    slots = Enum.map(cards, &%{card_id: &1.id, quantity: 1})

    assert {:ok, deck} =
             Decks.create_with_cards(
               %{
                 slots: slots,
                 title: "Imported",
                 mcdb_id: "build-import-1",
                 mcdb_type: :decklist,
                 hero_id: hero.id
               },
               load: [:deck_cards]
             )

    assert length(deck.deck_cards) == 2

    # Imported decks are public decklists on MarvelCDB — they stay published.
    assert deck.visibility == :published
    assert deck.state == :final
  end
end
