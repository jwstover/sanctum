defmodule Sanctum.Homebrew.CardPrivacyTest do
  @moduledoc """
  Leak tests: one per Card/CardSide read path. A private custom card must be
  invisible to other users and anonymous readers on every one of them. The
  fixture is deliberately adversarial — the custom card carries flavor text
  (guess-game bait) and an official-looking `set` string (game-setup bait).
  """

  use Sanctum.DataCase, async: true

  import Sanctum.AccountsFixtures

  alias Sanctum.Decks.Writeup
  alias Sanctum.Games
  alias Sanctum.Games.Card
  alias Sanctum.Games.CardSide
  alias Sanctum.Homebrew

  require Ash.Query

  @bait_set "privacy-test-modular"

  setup do
    creator = user_fixture()
    other = user_fixture()

    private_project =
      Homebrew.create_project!(%{name: "Secret Pack", attestation: true}, actor: creator)

    published_project =
      Homebrew.create_project!(%{name: "Public Pack", attestation: true}, actor: creator)

    published_project
    |> Homebrew.ensure_project_set(creator)
    |> Homebrew.set_set_visibility!(:published, actor: creator)

    private_card = custom_card!(private_project, creator, "secret-card.png")
    published_card = custom_card!(published_project, creator, "public-card.png")

    # Adversarial seeding (system-level writes, mimicking hostile data): give
    # the private card flavor text and an official-looking set string.
    [side] = private_card.card_sides

    side
    |> Ash.Changeset.for_update(:update, %{flavor: "A secret flavor.", ownership: :player})
    |> Ash.update!(authorize?: false)

    private_card
    |> Ash.Changeset.for_update(:update, %{set: @bait_set})
    |> Ash.update!(authorize?: false)

    %{
      creator: creator,
      other: other,
      admin: admin_user_fixture(),
      private_card: private_card,
      private_side: side,
      published_card: published_card
    }
  end

  defp custom_card!(project, actor, filename) do
    {:ok, card} =
      Homebrew.create_custom_card(
        %{
          homebrew_project_id: project.id,
          homebrew_set_id: Homebrew.ensure_project_set(project, actor).id,
          card_sides: [%{image_url: "https://img.test/#{filename}", filename: filename}]
        },
        actor
      )

    Ash.load!(card, :card_sides, authorize?: false)
  end

  defp browse_ids(actor) do
    CardSide
    |> Ash.Query.for_read(:browse, %{}, actor: actor)
    |> Ash.read!(actor: actor, page: [limit: 100, count: true])
    |> then(fn page -> {Enum.map(page.results, & &1.card_id), page.count} end)
  end

  describe "CardSide :browse (pool + deckbuilder)" do
    test "private custom invisible to others and anonymous, visible to creator/admin", ctx do
      {anon_ids, anon_count} = browse_ids(nil)
      {other_ids, _} = browse_ids(ctx.other)
      {creator_ids, creator_count} = browse_ids(ctx.creator)
      {admin_ids, _} = browse_ids(ctx.admin)

      refute ctx.private_card.id in anon_ids
      refute ctx.private_card.id in other_ids
      assert ctx.private_card.id in creator_ids
      assert ctx.private_card.id in admin_ids

      # The paginated count respects the filter too.
      assert creator_count == anon_count + 1
    end

    test "published customs are browsable by everyone", ctx do
      {anon_ids, _} = browse_ids(nil)
      {other_ids, _} = browse_ids(ctx.other)

      assert ctx.published_card.id in anon_ids
      assert ctx.published_card.id in other_ids
    end
  end

  describe "Card :guessable (guess game, nil actor)" do
    test "customs never enter the guessing pool — even published ones", ctx do
      published_side = hd(ctx.published_card.card_sides)

      published_side
      |> Ash.Changeset.for_update(:update, %{flavor: "Public flavor."})
      |> Ash.update!(authorize?: false)

      guessable_ids =
        Card
        |> Ash.Query.for_read(:guessable)
        |> Ash.read!(page: [limit: 100])
        |> Map.get(:results)
        |> Enum.map(& &1.id)

      refute ctx.private_card.id in guessable_ids
      refute ctx.published_card.id in guessable_ids
    end
  end

  describe "Ash.get by client-supplied id (/cards/:id, deck preview)" do
    test "not-found for others and anonymous, found for creator", ctx do
      assert {:error, _} = Ash.get(Card, ctx.private_card.id, actor: ctx.other)
      assert {:error, _} = Ash.get(Card, ctx.private_card.id)
      assert {:ok, _} = Ash.get(Card, ctx.private_card.id, actor: ctx.creator)
    end

    test "relationship loads filter both directions", ctx do
      # Card -> card_sides as another user: the side itself must not load.
      assert {:error, _} =
               Ash.get(Card, ctx.private_card.id, actor: ctx.other, load: [:card_sides])

      # CardSide -> card as another user: the side row is already invisible.
      assert {:error, _} =
               Ash.get(CardSide, ctx.private_side.id, actor: ctx.other, load: [:card])
    end
  end

  describe "code lookups (deck import, staples)" do
    test "custom codes resolve only for the creator", ctx do
      code = ctx.private_card.base_code
      side_code = hd(ctx.private_card.card_sides).code

      assert {:error, _} = Games.get_card_by_code(code, actor: ctx.other)
      assert {:error, _} = Games.get_card_by_code(code)
      assert {:ok, _} = Games.get_card_by_code(code, actor: ctx.creator)

      assert [] = Games.list_card_sides_by_codes!([side_code], actor: ctx.other)
      assert [] = Games.list_card_sides_by_codes!([side_code])
      assert [_side] = Games.list_card_sides_by_codes!([side_code], actor: ctx.creator)
    end
  end

  describe "card-by-set reads (game setup, actor-less)" do
    test "a custom card with an official-looking set string stays invisible", ctx do
      assert [] = Games.get_cards_by_set!(@bait_set)

      # The raw modular-set query game setup runs (create_game_encounter_deck).
      assert [] =
               Card
               |> Ash.Query.filter(set in ^[@bait_set])
               |> Ash.read!(domain: Sanctum.Games)

      # The creator's own game setup would see it (desired once custom
      # scenarios thread the actor through).
      assert [_card] = Games.get_cards_by_set!(@bait_set, actor: ctx.creator)
    end
  end

  describe "writeup card links (authorize?: false read)" do
    test "a writeup referencing a custom base_code never links to it", ctx do
      assert [%{kind: :inline, html: html}] =
               Writeup.render("[Leak Attempt](/card/#{ctx.private_card.base_code})")

      html = Phoenix.HTML.safe_to_string(html)

      refute html =~ "/cards/#{ctx.private_card.id}"
      assert html =~ "Leak Attempt"
    end
  end

  describe "set-keyed visibility" do
    setup ctx do
      # Published project, private set.
      pub_project =
        Homebrew.create_project!(%{name: "Pub Project", attestation: true}, actor: ctx.creator)

      Homebrew.set_project_visibility!(pub_project, :published, actor: ctx.creator)
      pub_project_card = custom_card!(pub_project, ctx.creator, "pubproj.png")

      # Private project, published set.
      priv_project =
        Homebrew.create_project!(%{name: "Priv Project", attestation: true}, actor: ctx.creator)

      priv_set = Homebrew.ensure_project_set(priv_project, ctx.creator)
      priv_project_card = custom_card!(priv_project, ctx.creator, "privproj.png")
      Homebrew.set_set_visibility!(priv_set, :published, actor: ctx.creator)

      %{pub_project_card: pub_project_card, priv_project_card: priv_project_card}
    end

    test "published project with a private set stays hidden", ctx do
      card = ctx.pub_project_card
      side = hd(card.card_sides)

      for actor <- [ctx.other, nil] do
        {ids, _} = browse_ids(actor)
        refute card.id in ids
        assert {:error, _} = Ash.get(Card, card.id, actor: actor)
        assert {:error, _} = Ash.get(CardSide, side.id, actor: actor)
        assert [] = Games.list_card_sides_by_codes!([side.code], actor: actor)
      end

      assert {:ok, _} = Ash.get(Card, card.id, actor: ctx.creator)
    end

    test "private project with a published set is visible to nil", ctx do
      card = ctx.priv_project_card
      side = hd(card.card_sides)

      for actor <- [ctx.other, nil] do
        {ids, _} = browse_ids(actor)
        assert card.id in ids
        assert {:ok, _} = Ash.get(Card, card.id, actor: actor)
        assert [_] = Games.list_card_sides_by_codes!([side.code], actor: actor)
      end

      # by-set read, nil actor
      card
      |> Ash.Changeset.for_update(:update, %{set: "set-keyed-bait"})
      |> Ash.update!(authorize?: false)

      assert [_] = Games.get_cards_by_set!("set-keyed-bait")
    end

    test "custom alts follow the set", ctx do
      official = create(Card, attrs: %{code: "91001", base_code: "91001"})
      create(CardSide, attrs: %{card_id: official.id, code: "91001a", side_identifier: "a"})

      {:ok, alt} =
        Homebrew.declare_alt_art(ctx.private_card.id, official.id, [], ctx.creator)

      alt_ids = fn actor ->
        Card
        |> Ash.get!(official.id, actor: actor, load: [:alts])
        |> Map.fetch!(:alts)
        |> Enum.map(& &1.id)
      end

      refute alt.id in alt_ids.(nil)
      refute alt.id in alt_ids.(ctx.other)
      assert alt.id in alt_ids.(ctx.creator)

      Homebrew.set_set_visibility!(
        Ash.get!(Sanctum.Homebrew.HomebrewSet, alt.homebrew_set_id, authorize?: false),
        :published,
        actor: ctx.creator
      )

      assert alt.id in alt_ids.(nil)
      assert alt.id in alt_ids.(ctx.other)
    end

    test "custom aspects follow the set", ctx do
      set =
        Sanctum.Homebrew.HomebrewSet
        |> Ash.get!(ctx.private_card.homebrew_set_id, authorize?: false)

      aspect =
        Ash.create!(
          Sanctum.Games.Aspect,
          %{
            key: "custom_#{System.unique_integer([:positive])}",
            label: "Custom",
            color: "#123456",
            origin: :custom,
            homebrew_project_id: set.homebrew_project_id,
            homebrew_set_id: set.id
          },
          authorize?: false
        )

      ids = fn actor -> actor |> then(&Games.list_aspects!(actor: &1)) |> Enum.map(& &1.key) end

      refute aspect.key in ids.(ctx.other)
      refute aspect.key in ids.(nil)
      assert aspect.key in ids.(ctx.creator)

      Homebrew.set_set_visibility!(set, :published, actor: ctx.creator)
      assert aspect.key in ids.(nil)
    end

    test "decks hide private custom cards from other viewers", ctx do
      deck_owner = Sanctum.AccountsFixtures.user_fixture()
      hero_card = create(Card, attrs: %{code: "91100", base_code: "91100", set: "dk_hero"})

      create(CardSide, attrs: %{card_id: hero_card.id, code: "91100a", side_identifier: "A"})

      create(CardSide,
        attrs: %{
          card_id: hero_card.id,
          code: "91100b",
          side_identifier: "B",
          type: :alter_ego,
          is_primary_side: false
        }
      )

      {:ok, hero} =
        Sanctum.Heroes.find_or_create_hero(%{
          hero_name: "Deck Hero",
          alter_ego_name: "Deck Ego",
          set: "dk_hero",
          base_code: "91100",
          card_id: hero_card.id
        })

      deck =
        Sanctum.Decks.Deck
        |> Ash.Changeset.for_create(:create, %{
          title: "Leaky deck",
          hero_id: hero.id,
          visibility: :published,
          owner_id: deck_owner.id
        })
        |> Ash.create!(authorize?: false)

      Ash.create!(
        Sanctum.Decks.DeckCard,
        %{deck_id: deck.id, card_id: ctx.private_card.id, quantity: 1},
        authorize?: false
      )

      for actor <- [ctx.other, nil] do
        deck =
          Sanctum.Decks.get_deck!(deck.id,
            actor: actor,
            load: [deck_cards: [card: :primary_side]]
          )

        refute Enum.any?(deck.deck_cards, &(&1.card && &1.card.id == ctx.private_card.id))
      end
    end
  end
end
