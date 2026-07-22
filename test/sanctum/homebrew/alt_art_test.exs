defmodule Sanctum.Homebrew.AltArtTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  import Sanctum.AccountsFixtures

  alias Sanctum.Decks.Writeup
  alias Sanctum.Games
  alias Sanctum.Games.Card
  alias Sanctum.Games.CardAlt
  alias Sanctum.Games.CardSide
  alias Sanctum.Homebrew

  require Ash.Query

  setup do
    creator = user_fixture()

    project =
      Homebrew.create_project!(%{name: "Alt Art Pack", attestation: true}, actor: creator)

    official = create(Card, attrs: %{code: "90001", base_code: "90001"})

    create(CardSide,
      attrs: %{
        card_id: official.id,
        name: "Official Hero",
        code: "90001a",
        side_identifier: "a",
        is_primary_side: true
      }
    )

    %{creator: creator, other: user_fixture(), project: project, official: official}
  end

  defp custom_card!(project, actor, filename \\ "fan-art.png") do
    {:ok, card} =
      Homebrew.create_custom_card(
        %{
          homebrew_project_id: project.id,
          card_sides: [%{image_url: "https://img.test/#{filename}", filename: filename}]
        },
        actor
      )

    Ash.load!(card, :card_sides, authorize?: false)
  end

  defp declare!(ctx, opts \\ []) do
    source = custom_card!(ctx.project, ctx.creator)

    {:ok, alt} =
      Homebrew.declare_alt_art(source.id, ctx.official.id, opts, ctx.creator)

    {source, alt}
  end

  describe "declare_alt_art" do
    test "converts the custom card into a CardAlt on the official card", ctx do
      source = custom_card!(ctx.project, ctx.creator)
      [side] = source.card_sides

      {:ok, alt} =
        Homebrew.declare_alt_art(
          source.id,
          ctx.official.id,
          [artist: "Jane Doe", side_identifier: "a"],
          ctx.creator
        )

      assert alt.origin == :custom
      assert alt.code == source.code
      assert alt.base_code == source.base_code
      assert alt.side_identifier == "a"
      assert alt.image_url == side.image_url
      assert alt.artist == "Jane Doe"
      assert alt.card_id == ctx.official.id
      assert alt.creator_id == ctx.creator.id
      assert alt.homebrew_project_id == ctx.project.id

      # Source card and its side are gone.
      assert {:error, _} = Ash.get(Card, source.id, authorize?: false)
      assert {:error, _} = Ash.get(CardSide, side.id, authorize?: false)
    end

    test "an official source card is rejected", ctx do
      assert {:error, %Ash.Error.Forbidden{}} =
               Homebrew.declare_alt_art(ctx.official.id, ctx.official.id, [], ctx.creator)
    end

    test "targeting another custom card is rejected", ctx do
      source = custom_card!(ctx.project, ctx.creator)
      target = custom_card!(ctx.project, ctx.creator, "other.png")

      assert {:error, error} =
               Homebrew.declare_alt_art(source.id, target.id, [], ctx.creator)

      assert Exception.message(error) =~ "official card"
    end

    test "a multi-sided source is rejected", ctx do
      front = custom_card!(ctx.project, ctx.creator, "front.png")
      back = custom_card!(ctx.project, ctx.creator, "back.png")
      {:ok, paired} = Homebrew.pair_custom_cards(front.id, back.id, ctx.creator)

      assert {:error, error} =
               Homebrew.declare_alt_art(paired.id, ctx.official.id, [], ctx.creator)

      assert Exception.message(error) =~ "single-sided"
    end

    test "another user's card cannot be declared", ctx do
      source = custom_card!(ctx.project, ctx.creator)

      assert {:error, %Ash.Error.Forbidden{}} =
               Homebrew.declare_alt_art(source.id, ctx.official.id, [], ctx.other)
    end

    test "a nil actor is forbidden", ctx do
      source = custom_card!(ctx.project, ctx.creator)

      assert {:error, %Ash.Error.Forbidden{}} =
               Homebrew.declare_alt_art(source.id, ctx.official.id, [], nil)
    end
  end

  describe "revert_alt_art" do
    test "mints a fresh custom card named after the target", ctx do
      {source, alt} = declare!(ctx, artist: "Jane Doe")

      {:ok, new_card} = Homebrew.revert_alt_art(alt.id, ctx.creator)

      assert new_card.origin == :custom
      assert new_card.homebrew_project_id == ctx.project.id
      # Identity is stable across the round trip: the alt's code is reused.
      assert new_card.code == source.code
      refute new_card.is_multi_sided

      [side] =
        new_card |> Ash.load!(:card_sides, authorize?: false) |> Map.fetch!(:card_sides)

      assert side.side_identifier == "a"
      assert side.is_primary_side
      assert side.code == new_card.code <> "a"
      assert side.name == "Official Hero"
      assert side.image_url == alt.image_url

      assert {:error, _} = Ash.get(CardAlt, alt.id, authorize?: false)
    end

    test "cross-user revert and destroy are not found", ctx do
      {_source, alt} = declare!(ctx)

      assert {:error, _} = Homebrew.revert_alt_art(alt.id, ctx.other)
      assert {:error, _} = Homebrew.destroy_alt_art(alt.id, ctx.other)
    end
  end

  describe "destroy_alt_art" do
    test "deletes the alt without minting a card", ctx do
      {source, alt} = declare!(ctx)

      assert :ok = Homebrew.destroy_alt_art(alt.id, ctx.creator)
      assert {:error, _} = Ash.get(CardAlt, alt.id, authorize?: false)
      assert {:error, _} = Ash.get(Card, source.id, authorize?: false)
    end
  end

  describe "privacy (detail-page shaped loads)" do
    test "private custom alts are visible only to their creator", ctx do
      {_source, alt} = declare!(ctx)

      official_alt =
        create(CardAlt, attrs: %{code: "90002", base_code: "90002", card_id: ctx.official.id})

      for {actor, sees_custom?} <- [
            {ctx.creator, true},
            {ctx.other, false},
            {nil, false},
            {admin_user_fixture(), true}
          ] do
        alts =
          Card
          |> Ash.get!(ctx.official.id, actor: actor, load: [:alts])
          |> Map.fetch!(:alts)
          |> Enum.map(& &1.id)

        assert official_alt.id in alts
        assert alt.id in alts == sees_custom?
      end
    end

    test "published-project custom alts are visible to everyone", ctx do
      {_source, alt} = declare!(ctx)
      Homebrew.set_project_visibility!(ctx.project, :published, actor: ctx.creator)

      for actor <- [ctx.other, nil] do
        alts =
          Card
          |> Ash.get!(ctx.official.id, actor: actor, load: [:alts])
          |> Map.fetch!(:alts)

        assert alt.id in Enum.map(alts, & &1.id)
      end
    end
  end

  describe "code-resolution pinning" do
    test "custom alts never resolve through by_code/by_codes", ctx do
      {_source, alt} = declare!(ctx)

      assert {:error, _} = Games.get_card_alt_by_code(alt.code)
      assert [] = Games.list_card_alts_by_codes!([alt.code])
      # Official alts still resolve.
      official_alt =
        create(CardAlt, attrs: %{code: "90002", base_code: "90002", card_id: ctx.official.id})

      assert {:ok, _} = Games.get_card_alt_by_code(official_alt.code)
    end

    test "writeup card links never resolve through a custom alt", ctx do
      {_source, alt} = declare!(ctx)

      assert [%{kind: :inline, html: html}] =
               Writeup.render("[Leak](/card/#{alt.code})")

      html = Phoenix.HTML.safe_to_string(html)
      refute html =~ "/cards/#{ctx.official.id}"
    end
  end

  describe "project integration" do
    test "list_project_alts and alt_count; project destroy cascades", ctx do
      {_source, alt} = declare!(ctx, artist: "Jane Doe")

      assert [listed] = Homebrew.list_project_alts(ctx.project.id, ctx.creator)
      assert listed.id == alt.id
      assert listed.card.primary_side.name == "Official Hero"

      assert %{alt_count: 1} =
               Homebrew.get_project!(ctx.project.id, actor: ctx.creator, load: [:alt_count])

      # Other users see no private alts through the list.
      assert [] = Homebrew.list_project_alts(ctx.project.id, ctx.other)

      :ok = Homebrew.destroy_project(ctx.project, actor: ctx.creator)
      assert {:error, _} = Ash.get(CardAlt, alt.id, authorize?: false)
    end

    test "collection ownership is unaffected by custom alts", ctx do
      {_source, _alt} = declare!(ctx)

      owned =
        Card
        |> Ash.get!(ctx.official.id, actor: ctx.creator, load: [:owned])
        |> Map.fetch!(:owned)

      refute owned
    end
  end
end
