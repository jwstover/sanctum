defmodule Sanctum.CollectionsTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  import Sanctum.AccountsFixtures

  alias Sanctum.Catalog.Pack
  alias Sanctum.Collections
  alias Sanctum.Collections.CollectionCard
  alias Sanctum.Collections.CollectionPack
  alias Sanctum.Games.Card
  alias Sanctum.Games.CardAlt

  require Ash.Query

  defp pack_fixture do
    create(Pack, action: :upsert_from_marvelcdb)
  end

  defp owned?(card, user) do
    Ash.get!(Card, card.id, actor: user, load: [:owned]).owned
  end

  defp override(card, user) do
    CollectionCard
    |> Ash.Query.filter(card_id == ^card.id)
    |> Ash.read_one!(actor: user)
  end

  describe "add_pack/remove_pack" do
    setup do
      %{user: user_fixture(), pack: pack_fixture()}
    end

    test "add_pack is idempotent", %{user: user, pack: pack} do
      assert {:ok, _} = Collections.add_pack(pack.id, actor: user)
      assert {:ok, _} = Collections.add_pack(pack.id, actor: user)

      assert [%CollectionPack{pack_id: pack_id}] =
               Collections.list_collection_packs!(actor: user)

      assert pack_id == pack.id
    end

    test "remove_pack is idempotent", %{user: user, pack: pack} do
      Collections.add_pack!(pack.id, actor: user)

      assert :ok = Collections.remove_pack(pack.id, user)
      assert :ok = Collections.remove_pack(pack.id, user)
      assert [] = Collections.list_collection_packs!(actor: user)
    end

    test "owned_pack_ids and pack_owned?", %{user: user, pack: pack} do
      other_pack = pack_fixture()
      Collections.add_pack!(pack.id, actor: user)

      assert Collections.owned_pack_ids(user) == MapSet.new([pack.id])
      assert Collections.pack_owned?(pack.id, user)
      refute Collections.pack_owned?(other_pack.id, user)
      assert Collections.owned_pack_ids(nil) == MapSet.new()
      refute Collections.pack_owned?(pack.id, nil)
    end
  end

  describe ":owned calculation" do
    setup do
      %{user: user_fixture(), pack: pack_fixture()}
    end

    test "owned via the card's own pack", %{user: user, pack: pack} do
      card = create(Card, attrs: %{pack_id: pack.id})

      refute owned?(card, user)
      Collections.add_pack!(pack.id, actor: user)
      assert owned?(card, user)
    end

    test "owned via a reprint's pack", %{user: user, pack: pack} do
      card = create(Card)
      create(CardAlt, attrs: %{card_id: card.id, pack_id: pack.id})

      refute owned?(card, user)
      Collections.add_pack!(pack.id, actor: user)
      assert owned?(card, user)
    end

    test "false for a nil actor even when someone owns the pack", %{user: user, pack: pack} do
      card = create(Card, attrs: %{pack_id: pack.id})
      Collections.add_pack!(pack.id, actor: user)

      refute owned?(card, nil)
    end

    test "another user's collection does not leak", %{user: user, pack: pack} do
      card = create(Card, attrs: %{pack_id: pack.id})
      Collections.add_pack!(pack.id, actor: user)

      refute owned?(card, user_fixture())
    end

    test ":owned override grants ownership with no packs", %{user: user} do
      card = create(Card)

      Collections.set_card_status!(card.id, :owned, actor: user)
      assert owned?(card, user)
    end

    test ":excluded override beats the card's own pack", %{user: user, pack: pack} do
      card = create(Card, attrs: %{pack_id: pack.id})
      Collections.add_pack!(pack.id, actor: user)

      Collections.set_card_status!(card.id, :excluded, actor: user)
      refute owned?(card, user)
    end

    test ":excluded override beats a reprint's pack", %{user: user, pack: pack} do
      card = create(Card)
      create(CardAlt, attrs: %{card_id: card.id, pack_id: pack.id})
      Collections.add_pack!(pack.id, actor: user)

      Collections.set_card_status!(card.id, :excluded, actor: user)
      refute owned?(card, user)
    end

    test "card side mirrors the card's ownership", %{user: user, pack: pack} do
      card = create(Card, attrs: %{pack_id: pack.id})
      side = create(Sanctum.Games.CardSide, attrs: %{card_id: card.id})
      Collections.add_pack!(pack.id, actor: user)

      assert Ash.load!(side, :owned, actor: user).owned
      refute Ash.load!(side, :owned, actor: user_fixture()).owned
    end
  end

  describe "toggle_card/2" do
    setup do
      %{user: user_fixture(), pack: pack_fixture()}
    end

    test "owned via pack -> records an :excluded override", %{user: user, pack: pack} do
      card = create(Card, attrs: %{pack_id: pack.id})
      Collections.add_pack!(pack.id, actor: user)

      refute Collections.toggle_card(card.id, user)
      refute owned?(card, user)
      assert %CollectionCard{status: :excluded} = override(card, user)
    end

    test "excluded despite pack -> destroys the override", %{user: user, pack: pack} do
      card = create(Card, attrs: %{pack_id: pack.id})
      Collections.add_pack!(pack.id, actor: user)
      Collections.set_card_status!(card.id, :excluded, actor: user)

      assert Collections.toggle_card(card.id, user)
      assert owned?(card, user)
      refute override(card, user)
    end

    test "not owned, no pack -> records an :owned override", %{user: user} do
      card = create(Card)

      assert Collections.toggle_card(card.id, user)
      assert owned?(card, user)
      assert %CollectionCard{status: :owned} = override(card, user)
    end

    test "owned only via override -> destroys the override", %{user: user} do
      card = create(Card)
      Collections.set_card_status!(card.id, :owned, actor: user)

      refute Collections.toggle_card(card.id, user)
      refute owned?(card, user)
      refute override(card, user)
    end

    test "redundant :owned override plus pack flips straight to :excluded", %{
      user: user,
      pack: pack
    } do
      card = create(Card, attrs: %{pack_id: pack.id})
      Collections.set_card_status!(card.id, :owned, actor: user)
      Collections.add_pack!(pack.id, actor: user)

      refute Collections.toggle_card(card.id, user)
      assert %CollectionCard{status: :excluded} = override(card, user)
    end
  end

  describe "privacy policies" do
    setup do
      %{user: user_fixture(), other: user_fixture(), pack: pack_fixture()}
    end

    test "reads are scoped to the actor", %{user: user, other: other, pack: pack} do
      Collections.add_pack!(pack.id, actor: user)
      Collections.set_card_status!(create(Card).id, :owned, actor: user)

      assert [] = Collections.list_collection_packs!(actor: other)
      assert [] = Collections.list_card_overrides!(actor: other)
      assert [] = Ash.read!(CollectionPack, actor: other)
      assert [] = Ash.read!(CollectionCard, actor: other)
    end

    test "a nil actor reads nothing", %{user: user, pack: pack} do
      Collections.add_pack!(pack.id, actor: user)

      assert [] = Ash.read!(CollectionPack, actor: nil)
    end

    test "destroys cannot touch another user's rows", %{user: user, other: other, pack: pack} do
      Collections.add_pack!(pack.id, actor: user)

      assert :ok = Collections.remove_pack(pack.id, other)
      assert [_] = Collections.list_collection_packs!(actor: user)
    end

    test "creates cannot smuggle another user's id", %{user: user, other: other, pack: pack} do
      assert {:error, %Ash.Error.Invalid{}} =
               CollectionPack
               |> Ash.Changeset.for_create(:add, %{pack_id: pack.id, user_id: other.id},
                 actor: user
               )
               |> Ash.create()
    end
  end
end
