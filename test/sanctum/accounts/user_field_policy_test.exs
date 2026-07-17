defmodule Sanctum.Accounts.UserFieldPolicyTest do
  use Sanctum.DataCase, async: false

  import Sanctum.AccountsFixtures
  import Sanctum.Factory

  alias Sanctum.Accounts.User

  describe "reading another user" do
    test "public profile fields are visible, private fields are forbidden" do
      user = user_fixture(username: "visible_handle", avatar_url: "https://example.com/a.png")
      other = user_fixture()

      read = Ash.get!(User, user.id, actor: other)

      assert to_string(read.username) == "visible_handle"
      assert read.avatar_url == "https://example.com/a.png"
      assert %Ash.ForbiddenField{} = read.email
      assert %Ash.ForbiddenField{} = read.confirmed_at
      assert %Ash.ForbiddenField{} = read.admin
      assert %Ash.ForbiddenField{} = read.hashed_password
    end

    test "anonymous reads succeed with the same masking" do
      user = user_fixture(username: "anon_visible")

      read = Ash.get!(User, user.id, actor: nil, authorize?: true)

      assert to_string(read.username) == "anon_visible"
      assert %Ash.ForbiddenField{} = read.email
    end
  end

  test "users see their own email" do
    user = user_fixture()

    read = Ash.get!(User, user.id, actor: user)

    assert read.email == user.email
    assert read.admin == false
  end

  test "admins see other users' private fields" do
    user = user_fixture()
    admin = admin_user_fixture()

    read = Ash.get!(User, user.id, actor: admin)

    assert read.email == user.email
  end

  test "anonymous deck reads load the owner with a masked email" do
    user = user_fixture(username: "deck_owner")
    deck = deck_fixture(user.id)

    loaded = Ash.get!(Sanctum.Decks.Deck, deck.id, actor: nil, authorize?: true, load: [:owner])

    assert to_string(loaded.owner.username) == "deck_owner"
    assert %Ash.ForbiddenField{} = loaded.owner.email
  end

  # A minimal valid native deck (hero card with both sides) owned by a user.
  defp deck_fixture(owner_id) do
    card =
      create(Sanctum.Games.Card,
        attrs: %{base_code: "90101", code: "90101a", set: "spider_man", is_multi_sided: true}
      )

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: card.id,
        name: "Spider-Man",
        type: :hero,
        code: "90101a",
        side_identifier: "A",
        is_primary_side: true
      }
    )

    create(Sanctum.Games.CardSide,
      attrs: %{
        card_id: card.id,
        name: "Peter Parker",
        type: :alter_ego,
        code: "90101b",
        side_identifier: "B",
        is_primary_side: false
      }
    )

    {:ok, hero} =
      Sanctum.Heroes.find_or_create_hero(%{
        hero_name: "Spider-Man",
        alter_ego_name: "Peter Parker",
        set: "spider_man",
        base_code: "90101",
        card_id: card.id
      })

    Sanctum.Decks.Deck
    |> Ash.Changeset.for_create(:create, %{
      title: "Policy Test Deck",
      hero_id: hero.id,
      source: :native,
      owner_id: owner_id
    })
    |> Ash.create!(authorize?: false)
  end
end
