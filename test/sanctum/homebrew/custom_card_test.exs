defmodule Sanctum.Homebrew.CustomCardTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  import Sanctum.AccountsFixtures

  alias Sanctum.Games.Card
  alias Sanctum.Homebrew

  require Ash.Query

  setup do
    creator = user_fixture()

    project =
      Homebrew.create_project!(%{name: "My Pack", attestation: true}, actor: creator)

    %{creator: creator, other: user_fixture(), project: project}
  end

  defp create_card!(project, actor, sides) do
    {:ok, card} =
      Homebrew.create_custom_card(
        %{homebrew_project_id: project.id, card_sides: sides},
        actor
      )

    Ash.load!(card, :card_sides, authorize?: false)
  end

  describe "create_custom" do
    test "mints origin, codes, and side conventions", ctx do
      card =
        create_card!(ctx.project, ctx.creator, [
          %{image_url: "https://img.test/a.png", filename: "spider_swing-kick.png"}
        ])

      assert card.origin == :custom
      assert card.homebrew_project_id == ctx.project.id
      assert "custom-" <> _uuid = card.base_code
      assert card.code == card.base_code
      refute card.is_multi_sided

      assert [side] = card.card_sides
      assert side.code == card.code <> "a"
      assert side.side_identifier == "a"
      assert side.is_primary_side
      assert side.name == "Spider Swing Kick"
      assert side.image_url == "https://img.test/a.png"
    end

    test "two sides make a multi-sided card", ctx do
      card =
        create_card!(ctx.project, ctx.creator, [
          %{image_url: "https://img.test/front.png", name: "Hero Face"},
          %{image_url: "https://img.test/back.png", name: "Alter-Ego Face"}
        ])

      assert card.is_multi_sided

      assert [%{side_identifier: "a", is_primary_side: true}, %{side_identifier: "b"}] =
               Enum.sort_by(card.card_sides, & &1.side_identifier)
    end

    test "name falls back to Untitled without a filename", ctx do
      card = create_card!(ctx.project, ctx.creator, [%{image_url: "https://img.test/x.png"}])

      assert [%{name: "Untitled"}] = card.card_sides
    end

    test "a side without an image is rejected", ctx do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Homebrew.create_custom_card(
                 %{homebrew_project_id: ctx.project.id, card_sides: [%{name: "No Image"}]},
                 ctx.creator
               )

      assert Exception.message(error) =~ "missing an image"
    end

    test "cannot create into another user's project", ctx do
      assert {:error, %Ash.Error.Forbidden{}} =
               Homebrew.create_custom_card(
                 %{
                   homebrew_project_id: ctx.project.id,
                   card_sides: [%{image_url: "https://img.test/a.png"}]
                 },
                 ctx.other
               )
    end

    test "cannot smuggle origin/code/set through create_custom", ctx do
      for forbidden <- [%{origin: :official}, %{code: "01001"}, %{set: "core"}] do
        attrs =
          Map.merge(
            %{
              homebrew_project_id: ctx.project.id,
              card_sides: [%{image_url: "https://img.test/a.png"}]
            },
            forbidden
          )

        assert {:error, _} = Homebrew.create_custom_card(attrs, ctx.creator)
      end
    end
  end

  describe "update_custom / destroy_custom" do
    setup ctx do
      %{card: create_card!(ctx.project, ctx.creator, [%{image_url: "https://img.test/a.png"}])}
    end

    test "creator can update card-level flags", ctx do
      assert {:ok, updated} =
               ctx.card
               |> Ash.Changeset.for_update(:update_custom, %{deck_limit: 1, unique: true},
                 actor: ctx.creator
               )
               |> Ash.update()

      assert updated.deck_limit == 1
      assert updated.unique
    end

    test "another user cannot update or destroy the card", ctx do
      assert {:error, _} =
               ctx.card
               |> Ash.Changeset.for_update(:update_custom, %{deck_limit: 1}, actor: ctx.other)
               |> Ash.update()

      assert {:error, _} = Homebrew.destroy_custom_card(ctx.card.id, ctx.other)
    end

    test "creator can destroy; sides cascade", ctx do
      [side] = ctx.card.card_sides

      assert :ok = Homebrew.destroy_custom_card(ctx.card.id, ctx.creator)
      assert {:error, _} = Ash.get(Card, ctx.card.id, authorize?: false)
      assert {:error, _} = Ash.get(Sanctum.Games.CardSide, side.id, authorize?: false)
    end

    test "custom actions cannot touch official cards", ctx do
      official = create(Card)

      assert {:error, _} =
               official
               |> Ash.Changeset.for_update(:update_custom, %{deck_limit: 1}, actor: ctx.creator)
               |> Ash.update()
    end
  end

  describe "official catalog boundaries" do
    test "non-admins cannot use the official mutations", ctx do
      assert {:error, %Ash.Error.Forbidden{}} =
               Card
               |> Ash.Changeset.for_create(:create, %{code: "88888", base_code: "88888"},
                 actor: ctx.creator
               )
               |> Ash.create()
    end

    test "sync-style numeric upserts cannot collide with custom rows", ctx do
      card = create_card!(ctx.project, ctx.creator, [%{image_url: "https://img.test/a.png"}])

      synced = create(Card, attrs: %{code: "77777", base_code: "77777"})

      assert synced.id != card.id
      assert Ash.get!(Card, card.id, authorize?: false).origin == :custom
    end
  end
end
