defmodule Sanctum.CardSyncTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  alias Sanctum.CardImages
  alias Sanctum.CardSync
  alias Sanctum.Games

  # Trimmed real shapes from the /cards/?encounter=1 payload, covering every
  # multi-sided representation MarvelCDB uses.
  @entries [
    # Single-sided card
    %{
      "code" => "01050",
      "name" => "Hulk",
      "type_code" => "ally",
      "faction_code" => "aggression",
      "pack_code" => "core",
      "card_set_code" => nil,
      "quantity" => 1,
      "imagesrc" => "/bundles/cards/01050.png"
    },
    # Hero pair: both sides are their own entries with their own images
    %{
      "code" => "01001a",
      "name" => "Spider-Man",
      "type_code" => "hero",
      "faction_code" => "hero",
      "pack_code" => "core",
      "card_set_code" => "spider_man",
      "imagesrc" => "/bundles/cards/01001a.png"
    },
    %{
      "code" => "01001b",
      "name" => "Peter Parker",
      "type_code" => "alter_ego",
      "faction_code" => "hero",
      "pack_code" => "core",
      "card_set_code" => "spider_man",
      "imagesrc" => "/bundles/cards/01001b.png"
    },
    # 3-form hero (Angel): three sibling entries, no parent, c is orphaned
    %{
      "code" => "42001a",
      "name" => "Angel",
      "type_code" => "hero",
      "pack_code" => "angel",
      "imagesrc" => "/bundles/cards/42001a.png"
    },
    %{
      "code" => "42001b",
      "name" => "Warren Worthington III",
      "type_code" => "alter_ego",
      "pack_code" => "angel",
      "imagesrc" => "/bundles/cards/42001b.png"
    },
    %{
      "code" => "42001c",
      "name" => "Archangel",
      "type_code" => "hero",
      "pack_code" => "angel",
      "imagesrc" => "/bundles/cards/42001c.png"
    },
    # Main scheme: MarvelCDB's scans are inverted relative to the stage. The
    # parent pairs `imagesrc` with `text` (the scheme/1B face) and
    # `backimagesrc` with `back_text` (the setup/1A face), but the per-side
    # entries don't line up — the "a" (setup) side has no image and the "b"
    # (scheme) side ships the *setup* scan (`01097b.png`). Each side must get
    # the parent scan whose text matches it, not its own imagesrc.
    %{
      "code" => "01097",
      "name" => "The Break-In!",
      "type_code" => "main_scheme",
      "pack_code" => "core",
      "card_set_code" => "rhino",
      "stage" => "1",
      "double_sided" => true,
      "text" => "If this stage is completed, the players lose the game.",
      "back_text" => "Contents: Rhino (I) and Rhino (II). Setup: Advance to stage 1B.",
      "imagesrc" => "/bundles/cards/01097.png",
      "backimagesrc" => "/bundles/cards/01097b.png"
    },
    %{
      "code" => "01097a",
      "name" => "The Break-In!",
      "type_code" => "main_scheme",
      "pack_code" => "core",
      "card_set_code" => "rhino",
      "stage" => "1A",
      "text" => "Contents: Rhino (I) and Rhino (II). Setup: Advance to stage 1B.",
      "imagesrc" => nil
    },
    %{
      "code" => "01097b",
      "name" => "The Break-In!",
      "type_code" => "main_scheme",
      "pack_code" => "core",
      "card_set_code" => "rhino",
      "stage" => "1B",
      "text" => "If this stage is completed, the players lose the game.",
      "imagesrc" => "/bundles/cards/01097b.png"
    },
    # Double-sided card with NO side entries (Intangible): synthesize both
    %{
      "code" => "26002",
      "name" => "Intangible",
      "type_code" => "upgrade",
      "faction_code" => "hero",
      "pack_code" => "vision",
      "permanent" => true,
      "double_sided" => true,
      "text" => "Mass form.",
      "back_name" => "Dense",
      "back_text" => "Mass form, but dense.",
      "imagesrc" => "/bundles/cards/26002a.jpg",
      "backimagesrc" => "/bundles/cards/26002b.png"
    },
    # Pack-payload shape: hidden B-side entries are omitted from /cards/{pack}
    # (only the all-cards payload includes them) — the B side must be
    # synthesized from the parent
    %{
      "code" => "77001",
      "name" => "Hidden Agenda",
      "type_code" => "main_scheme",
      "pack_code" => "future",
      "stage" => "1",
      "double_sided" => true,
      "back_text" => "Scheme text for the hidden side.",
      "imagesrc" => "/bundles/cards/77001.png",
      "backimagesrc" => "/bundles/cards/77001b.png"
    },
    %{
      "code" => "77001a",
      "name" => "Hidden Agenda",
      "type_code" => "main_scheme",
      "pack_code" => "future",
      "stage" => "1A",
      "imagesrc" => nil
    },
    # Card with no scan at all
    %{
      "code" => "99001",
      "name" => "No Scan Yet",
      "type_code" => "event",
      "pack_code" => "future"
    }
  ]

  setup do
    Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
      Req.Test.json(conn, @entries)
    end)

    :ok
  end

  test "syncs every multi-sided card shape with bucket image URLs" do
    assert {:ok, %{data: %{synced: 7, failures: []}, images: nil}} =
             CardSync.run(packs: :all, images?: false)

    # Single-sided card gets one side with its own image
    assert [%{side_identifier: "a", image_url: url}] = sides("01050")
    assert url == bucket_url("01050.png")

    # Hero pair
    assert [%{code: "01001a"}, %{code: "01001b"}] = sides("01001")

    # 3-form hero: all three sides on ONE card
    assert [%{name: "Angel"}, %{name: "Warren Worthington III"}, %{name: "Archangel"}] =
             sides("42001")

    # Main scheme: images resolve by matching each side's text to the parent's
    # front/back scan, NOT by side letter — so the setup "a" side gets the
    # `b`-suffixed scan and the scheme "b" side gets the unsuffixed scan (the
    # opposite of what the filenames suggest). Stages parse to integers.
    assert [side_a, side_b] = sides("01097")
    assert side_a.image_url == bucket_url("01097b.png")
    assert side_a.stage == 1
    assert side_b.image_url == bucket_url("01097.png")

    # Intangible: both sides synthesized from the lone parent entry
    assert [front, back] = sides("26002")
    assert front.name == "Intangible"
    assert front.image_url == bucket_url("26002a.jpg")
    assert back.name == "Dense"
    assert back.text == "Mass form, but dense."
    assert back.image_url == bucket_url("26002b.png")
    assert Games.get_card_by_code!("26002").permanent

    # Hidden B side (absent from pack payloads) synthesized from the parent
    assert [hidden_a, hidden_b] = sides("77001")
    assert hidden_a.image_url == bucket_url("77001.png")
    assert hidden_b.code == "77001b"
    assert hidden_b.text == "Scheme text for the hidden side."
    assert hidden_b.image_url == bucket_url("77001b.png")

    # No scan -> nil image_url (UI falls back to card backs)
    assert [%{image_url: nil}] = sides("99001")
  end

  test "re-running updates existing sides instead of skipping them" do
    assert {:ok, _} = CardSync.run(packs: :all, images?: false)

    # Simulate a pre-mirror row still pointing at marvelcdb.com
    {:ok, side} = Games.get_card_side_by_code("01001a")

    {:ok, _} =
      Games.update_card_side(side, %{image_url: "https://marvelcdb.com/old.png"},
        authorize?: false
      )

    assert {:ok, %{data: %{synced: 7, failures: []}}} =
             CardSync.run(packs: :all, images?: false)

    {:ok, side} = Games.get_card_side_by_code("01001a")
    assert side.image_url == bucket_url("01001a.png")
  end

  test "migrates legacy sides stored under an unsuffixed code" do
    # Older sync logic keyed sides by the raw entry code ("01001"); the new
    # payload uses suffixed codes ("01001a") for the same physical side.
    {:ok, card} =
      Games.create_card(%{base_code: "01001", code: "01001", is_multi_sided: true},
        authorize?: false
      )

    {:ok, _} =
      Games.create_card_side(
        %{
          card_id: card.id,
          code: "01001",
          side_identifier: "a",
          is_primary_side: true,
          name: "Spider-Man (legacy row)"
        },
        authorize?: false
      )

    assert {:ok, %{data: %{failures: []}}} = CardSync.run(packs: :all, images?: false)

    # The legacy row was updated in place, not duplicated
    assert [side_a, _side_b] = sides("01001")
    assert side_a.code == "01001a"
    assert side_a.name == "Spider-Man"
  end

  test "does not duplicate a side whose stored enum value no longer loads" do
    assert {:ok, _} = CardSync.run(packs: :all, images?: false)

    {:ok, card} = Games.get_card_by_code("01001")

    # Corrupt an existing side the way legacy prod data is corrupt: an
    # ownership-only faction value ("encounter") left in the aspect column,
    # which the current CardAspect enum can no longer load.
    Sanctum.Repo.query!("UPDATE card_sides SET aspect = 'encounter' WHERE code = '01001a'")

    count_sql = "SELECT count(*) FROM card_sides WHERE card_id::text = $1"
    before = Sanctum.Repo.query!(count_sql, [card.id]).rows

    assert {:error, %{data: %{failures: failures}}} = CardSync.run(packs: :all, images?: false)

    # The card group failed, but NOT with a duplicate-side constraint violation:
    # the un-loadable row's error propagates instead of being mistaken for "not
    # found" and re-inserted.
    assert {"01001", error} = Enum.find(failures, fn {code, _} -> code == "01001" end)
    refute inspect(error) =~ "has already been taken"

    # No duplicate side was inserted for the card.
    assert before == Sanctum.Repo.query!(count_sql, [card.id]).rows
  end

  test "dry run writes nothing" do
    assert {:ok, :dry_run} = CardSync.run(packs: :all, dry_run?: true)
    assert {:error, _} = Games.get_card_side_by_code("01001a")
  end

  test "reprints become CardAlts of the canonical card, not new cards" do
    Req.Test.stub(Sanctum.MarvelCdb, fn conn ->
      Req.Test.json(conn, [
        %{
          "code" => "01088",
          "name" => "Energy",
          "type_code" => "resource",
          "faction_code" => "basic",
          "pack_code" => "core",
          "resource_energy" => 2,
          "imagesrc" => "/bundles/cards/01088.png"
        },
        %{
          "code" => "16021",
          "name" => "Energy",
          "type_code" => "resource",
          "faction_code" => "basic",
          "pack_code" => "gmw",
          "duplicate_of_code" => "01088",
          "imagesrc" => "/bundles/cards/16021.png"
        }
      ])
    end)

    assert {:ok, %{data: %{failures: []}}} = CardSync.run(packs: :all, images?: false)

    # The canonical card exists; the reprint did NOT create a second Card.
    assert {:ok, canonical} = Games.get_card_by_code("01088")
    refute match?({:ok, %Games.Card{}}, Games.get_card_by_code("16021"))

    # A CardAlt records the reprint and points at the canonical card.
    assert {:ok, alt} = Games.get_card_alt_by_code("16021", load: [:card])
    assert alt.card_id == canonical.id
    assert alt.image_url == bucket_url("16021.png")

    # Deck resolution: a slot listing the reprint code resolves to the canonical.
    assert {:ok, resolved} = Sanctum.MarvelCdb.load_card("16021")
    assert resolved.id == canonical.id
  end

  defp sides(base_code) do
    card = Games.get_card_by_code!(base_code, load: [:card_sides])
    Enum.sort_by(card.card_sides, & &1.side_identifier)
  end

  defp bucket_url(filename), do: CardImages.base_url() <> "/cards/" <> filename
end
