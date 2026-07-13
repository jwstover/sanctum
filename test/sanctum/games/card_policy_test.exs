defmodule Sanctum.Games.CardPolicyTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  import Sanctum.AccountsFixtures

  alias Sanctum.Games

  defp card_attrs, do: %{base_code: "90001", code: "90001"}

  defp side_attrs(card) do
    %{card_id: card.id, code: "90001", side_identifier: "a", name: "Policy Test Card"}
  end

  defp create_card_as_system do
    Games.create_card!(card_attrs(), authorize?: false)
  end

  describe "catalog mutations" do
    test "are forbidden without an actor" do
      assert {:error, %Ash.Error.Forbidden{}} = Games.create_card(card_attrs())
    end

    test "are forbidden for non-admin actors" do
      user = user_fixture()

      assert {:error, %Ash.Error.Forbidden{}} = Games.create_card(card_attrs(), actor: user)

      card = create_card_as_system()

      assert {:error, %Ash.Error.Forbidden{}} =
               Games.create_card_side(side_attrs(card), actor: user)

      assert {:error, %Ash.Error.Forbidden{}} = Ash.destroy(card, actor: user)
    end

    test "are allowed for admin actors" do
      admin = admin_user_fixture()

      assert {:ok, card} = Games.create_card(card_attrs(), actor: admin)
      assert {:ok, side} = Games.create_card_side(side_attrs(card), actor: admin)

      assert {:ok, _} = Games.update_card_side(side, %{name: "Renamed"}, actor: admin)

      # A side-less card, so the destroy isn't blocked by the card_sides FK —
      # we're asserting the destroy policy, not cascade behavior.
      destroyable = Games.create_card!(%{base_code: "90002", code: "90002"}, authorize?: false)
      assert :ok = Ash.destroy(destroyable, actor: admin)
    end

    test "are allowed actor-less with authorize?: false (system sync path)" do
      card = create_card_as_system()
      assert {:ok, side} = Games.create_card_side(side_attrs(card), authorize?: false)

      assert {:ok, _} =
               Games.update_card_side(side, %{name: "Renamed"}, authorize?: false)
    end
  end

  describe "catalog reads" do
    test "stay open to everyone, including nil actors" do
      card = create_card_as_system()
      Games.create_card_side!(side_attrs(card), authorize?: false)

      assert {:ok, _} = Games.get_card_by_code("90001", actor: nil)
      assert {:ok, _} = Games.get_card_side_by_code("90001", actor: nil)
      assert {:ok, _} = Games.list_cards(actor: user_fixture())
    end
  end
end
