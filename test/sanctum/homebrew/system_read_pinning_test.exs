defmodule Sanctum.Homebrew.SystemReadPinningTest do
  @moduledoc """
  System reads that run with `authorize?: false` (or raw SQL) skip the Card
  read policy, so they must pin `origin == :official` themselves. These tests
  publish the custom set — the policy would then admit the row — and assert
  the pinned paths still never surface it.
  """

  # Search.ValueCache is global, so this module can't run async.
  use Sanctum.DataCase, async: false

  import Sanctum.AccountsFixtures

  alias Sanctum.Decks.Writeup
  alias Sanctum.Games
  alias Sanctum.Games.Card
  alias Sanctum.Games.CardSide
  alias Sanctum.Homebrew
  alias Sanctum.Search.ValueCache
  alias Sanctum.Search.Values

  setup do
    ValueCache.reset()

    creator = user_fixture()
    project = Homebrew.create_project!(%{name: "Pinned", attestation: true}, actor: creator)
    set = Homebrew.ensure_project_set(project, creator)

    {:ok, card} =
      Homebrew.create_custom_card(
        %{
          homebrew_project_id: project.id,
          homebrew_set_id: set.id,
          card_sides: [%{image_url: "https://img.test/p.png", filename: "p.png"}]
        },
        creator
      )

    Homebrew.set_set_visibility!(set, :published, actor: creator)

    %{creator: creator, project: project, card: Ash.load!(card, :card_sides, authorize?: false)}
  end

  test "writeup links never resolve a custom card", ctx do
    assert [%{kind: :inline, html: html}] =
             Writeup.render("[Leak](/card/#{ctx.card.base_code})")

    refute Phoenix.HTML.safe_to_string(html) =~ "/cards/#{ctx.card.id}"
  end

  test "signature_cards never includes a custom card", ctx do
    hero_card = create(Card, attrs: %{code: "92000", base_code: "92000", set: "pin_hero"})
    create(CardSide, attrs: %{card_id: hero_card.id, code: "92000a", side_identifier: "A"})

    {:ok, hero} =
      Sanctum.Heroes.find_or_create_hero(%{
        hero_name: "Pin Hero",
        alter_ego_name: "Pin Ego",
        set: "pin_hero",
        base_code: "92000",
        card_id: hero_card.id
      })

    ctx.card
    |> Ash.Changeset.for_update(:update, %{set: "pin_hero"})
    |> Ash.update!(authorize?: false)

    ctx.card.card_sides
    |> hd()
    |> Ash.Changeset.for_update(:update, %{ownership: :hero, is_primary_side: true})
    |> Ash.update!(authorize?: false)

    refute ctx.card.id in Enum.map(Sanctum.Decks.signature_cards(hero.id), & &1.id)
  end

  test "alt code lookups never resolve a custom alt", ctx do
    official = create(Card, attrs: %{code: "92100", base_code: "92100"})
    create(CardSide, attrs: %{card_id: official.id, code: "92100a", side_identifier: "A"})

    {:ok, alt} = Homebrew.declare_alt_art(ctx.card.id, official.id, [], ctx.creator)

    assert {:error, _} = Games.get_card_alt_by_code(alt.code)
    assert [] = Games.list_card_alts_by_codes!([alt.code])
  end

  test "Values.traits/0 excludes custom-only traits", ctx do
    ctx.card.card_sides
    |> hd()
    |> Ash.Changeset.for_update(:update, %{traits: ["Zzz Custom Only Trait"]})
    |> Ash.update!(authorize?: false)

    ValueCache.reset()
    refute "Zzz Custom Only Trait" in Values.traits()
  end
end
