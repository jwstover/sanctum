defmodule Sanctum.MarvelCdbTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  alias Sanctum.MarvelCdb

  require Ash.Query

  @tag :skip
  test "loads a decklist" do
    mcdb_deck_id = "50919"

    assert {:ok, _} = MarvelCdb.load_deck(mcdb_deck_id)
  end

  @tag :external
  test "loads Rhino villain stages and creates proper Villain resource" do
    # Load the three Rhino stage cards
    rhino_stage_codes = ["01094", "01095", "01096"]

    # Load each card individually (this simulates what happens when cards are loaded)
    loaded_cards =
      Enum.map(rhino_stage_codes, fn code ->
        case MarvelCdb.load_card(code) do
          {:ok, card} -> card
          error -> flunk("Failed to load card #{code}: #{inspect(error)}")
        end
      end)

    # Verify all cards were created
    assert length(loaded_cards) == 3

    # Check that all cards are in the same set
    sets = Enum.map(loaded_cards, & &1.set) |> Enum.uniq()
    assert length(sets) == 1
    set_name = hd(sets)

    # Load all the card sides for these cards
    card_sides =
      Enum.flat_map(loaded_cards, fn card ->
        card_with_sides = Ash.load!(card, [:card_sides])
        card_with_sides.card_sides
      end)

    # Find the villain sides (should be one per card)
    villain_sides = Enum.filter(card_sides, &(&1.type == :villain))

    assert length(villain_sides) >= 3,
           "Expected at least 3 villain sides, got #{length(villain_sides)}"

    # Get the villain name from any villain side (they should all have the same name)
    villain_name = hd(villain_sides).name

    # Check that a Villain resource was created
    case Sanctum.Villains.get_by_set(set_name) do
      {:ok, villains} ->
        rhino_villain = Enum.find(villains, &(&1.villain_name == villain_name))
        assert rhino_villain, "Rhino villain not found in set #{set_name}"

        # Load the villain with its stage sides
        rhino_with_sides = Ash.load!(rhino_villain, [:stage_sides])

        # Should have at least 3 stages
        assert length(rhino_with_sides.stage_sides) >= 3,
               "Expected at least 3 stage sides, got #{length(rhino_with_sides.stage_sides)}"

        # Verify stage numbers are present
        stage_numbers =
          rhino_with_sides.stage_sides
          |> Enum.map(& &1.stage)
          |> Enum.filter(&(!is_nil(&1)))
          |> Enum.sort()

        assert 1 in stage_numbers, "Stage 1 not found"
        assert 2 in stage_numbers, "Stage 2 not found"
        assert 3 in stage_numbers, "Stage 3 not found"

        # Verify each stage has different stats (health should increase with stage)
        stages_with_health =
          rhino_with_sides.stage_sides
          |> Enum.filter(&(!is_nil(&1.health) and !is_nil(&1.stage)))
          |> Enum.sort_by(& &1.stage)

        if length(stages_with_health) >= 3 do
          [stage1, stage2, stage3 | _] = stages_with_health

          # Rhino should get stronger with each stage
          assert stage1.health.value <= stage2.health.value,
                 "Stage 2 health (#{stage2.health.value}) should be >= Stage 1 health (#{stage1.health.value})"

          assert stage2.health.value <= stage3.health.value,
                 "Stage 3 health (#{stage3.health.value}) should be >= Stage 2 health (#{stage2.health.value})"
        end

      error ->
        flunk("Failed to find villains in set #{set_name}: #{inspect(error)}")
    end
  end

  describe "create_card_from_entries/2 image resolution" do
    # MarvelCDB's main-scheme payload is internally inconsistent: the parent
    # double-sided entry pairs `imagesrc` with `text` and `backimagesrc` with
    # `back_text`, but the auto-generated per-side entries don't line up — the
    # "a" (setup) side has no image and the "b" (scheme) side ships the *back*
    # scan. Each Sanctum side must get the parent scan whose text matches it.
    test "assigns main-scheme side images by matching parent text, not side letter" do
      parent = %{
        "code" => "01097",
        "name" => "The Break-In!",
        "type_code" => "main_scheme",
        "card_set_code" => "rhino",
        "pack_code" => "core",
        "quantity" => 1,
        "double_sided" => true,
        "imagesrc" => "/bundles/cards/01097.png",
        "backimagesrc" => "/bundles/cards/01097b.png",
        "text" => "If this stage is completed, the players lose the game.",
        "back_text" => "Contents: Rhino (I) and Rhino (II). Setup: Advance to stage 1B.",
        "threat" => 7,
        "base_threat" => 0,
        "escalation_threat" => 1
      }

      side_a = %{
        "code" => "01097a",
        "name" => "The Break-In!",
        "type_code" => "main_scheme",
        "card_set_code" => "rhino",
        "pack_code" => "core",
        "double_sided" => false,
        "imagesrc" => nil,
        "text" => "Contents: Rhino (I) and Rhino (II). Setup: Advance to stage 1B."
      }

      side_b = %{
        "code" => "01097b",
        "name" => "The Break-In!",
        "type_code" => "main_scheme",
        "card_set_code" => "rhino",
        "pack_code" => "core",
        "double_sided" => false,
        # MarvelCDB puts the *back* scan on the scheme side — the bug source.
        "imagesrc" => "/bundles/cards/01097b.png",
        "text" => "If this stage is completed, the players lose the game.",
        "threat" => 7,
        "base_threat" => 0,
        "escalation_threat" => 1
      }

      assert {:ok, card} =
               MarvelCdb.create_card_from_entries([parent, side_a, side_b], image_url_fun: & &1)

      sides =
        card
        |> Ash.load!([:card_sides])
        |> Map.fetch!(:card_sides)
        |> Map.new(&{&1.side_identifier, &1})

      # Side "a" is the setup face → the "b"-suffixed (grayscale setup) scan.
      assert sides["a"].image_url == "/bundles/cards/01097b.png"
      # Side "b" is the scheme face → the unsuffixed (colored threat) scan.
      assert sides["b"].image_url == "/bundles/cards/01097.png"
    end
  end

  describe "create_card_from_entries/2 reprints" do
    test "stores the reprint's pack FK on the alt" do
      canonical = create(Sanctum.Games.Card, attrs: %{base_code: "01001", code: "01001"})

      pack =
        create(Sanctum.Catalog.Pack,
          action: :upsert_from_marvelcdb,
          attrs: %{code: "mystique", name: "Mystique"}
        )

      entry = %{
        "code" => "33001",
        "duplicate_of_code" => "01001",
        "pack_code" => "mystique",
        "card_set_code" => "mystique_hero",
        "quantity" => 1
      }

      assert {:ok, _card} = MarvelCdb.create_card_from_entries([entry], image_url_fun: & &1)

      alt =
        Sanctum.Games.CardAlt
        |> Ash.Query.filter(code == "33001")
        |> Ash.read_one!(authorize?: false)

      assert alt.card_id == canonical.id
      assert alt.pack == "mystique"
      assert alt.pack_id == pack.id
    end
  end

  describe "import_decklist/2" do
    # All referenced codes are pre-seeded in the catalog, so the import runs
    # entirely offline — no Req stub needed.
    test "captures MarvelCDB's date_creation/date_update as mcdb dates" do
      hero_card = create(Sanctum.Games.Card, attrs: %{base_code: "42001", code: "42001"})

      create(Sanctum.Games.CardSide,
        attrs: %{
          card_id: hero_card.id,
          name: "Import Hero",
          type: :hero,
          code: "42001a",
          side_identifier: "A",
          is_primary_side: true
        }
      )

      create(Sanctum.Games.CardSide,
        attrs: %{
          card_id: hero_card.id,
          name: "Import Alter Ego",
          type: :alter_ego,
          code: "42001b",
          side_identifier: "B",
          is_primary_side: false
        }
      )

      slot_card = create(Sanctum.Games.Card, attrs: %{base_code: "42002", code: "42002"})

      create(Sanctum.Games.CardSide,
        attrs: %{card_id: slot_card.id, code: "42002", side_identifier: "A"}
      )

      payload = %{
        "id" => 35_109,
        "name" => "Dated deck",
        "hero_code" => "42001a",
        "slots" => %{"42002" => 2},
        "date_creation" => "2024-01-15T00:10:13+00:00",
        "date_update" => "2024-01-21T16:02:07+00:00"
      }

      assert {:ok, deck} = MarvelCdb.import_decklist(payload)
      assert deck.mcdb_date_creation == ~U[2024-01-15 00:10:13Z]
      assert deck.mcdb_date_update == ~U[2024-01-21 16:02:07Z]
    end

    test "records the decklist API's like_count and stamps when it changed" do
      seed_like_catalog()

      assert {:ok, deck} = MarvelCdb.import_decklist(like_payload(%{"like_count" => 7}))
      assert deck.mcdb_like_count == 7
      assert %DateTime{} = deck.mcdb_social_synced_at
      # A fresh insert has no prior count to compare against.
      assert reload(deck).mcdb_like_changed_at == nil

      # Same count: no change stamp.
      backdate_like_changed_at(deck)
      assert {:ok, _} = MarvelCdb.import_decklist(like_payload(%{"like_count" => 7}))
      assert reload(deck).mcdb_like_changed_at == ~U[2024-01-01 00:00:00Z]

      # New count: restamped.
      assert {:ok, _} = MarvelCdb.import_decklist(like_payload(%{"like_count" => 9}))
      deck = reload(deck)
      assert deck.mcdb_like_count == 9
      assert DateTime.after?(deck.mcdb_like_changed_at, ~U[2024-01-01 00:00:00Z])
    end

    test "a payload without like_count leaves the stored social data alone" do
      seed_like_catalog()

      assert {:ok, deck} = MarvelCdb.import_decklist(like_payload(%{"like_count" => 12}))
      backdate_like_changed_at(deck)
      synced_at = reload(deck).mcdb_social_synced_at

      assert {:ok, _} = MarvelCdb.import_decklist(like_payload(%{}))
      deck = reload(deck)
      assert deck.mcdb_like_count == 12
      assert deck.mcdb_like_changed_at == ~U[2024-01-01 00:00:00Z]
      assert deck.mcdb_social_synced_at == synced_at
    end

    # Ironheart's shape: several hero-sided cards (suit versions) in one set.
    # Decks can be built on any version; all of them must resolve to a single
    # Hero keyed on the set's canonical (lowest base_code) card.
    test "decks built on different hero versions share one canonical Hero" do
      for version <- ["91001", "91002", "91003"] do
        card =
          create(Sanctum.Games.Card,
            attrs: %{base_code: version, code: version, set: "test_ironheart"}
          )

        create(Sanctum.Games.CardSide,
          attrs: %{
            card_id: card.id,
            name: "Test Ironheart",
            type: :hero,
            code: "#{version}a",
            side_identifier: "A",
            is_primary_side: true
          }
        )

        create(Sanctum.Games.CardSide,
          attrs: %{
            card_id: card.id,
            name: "Test Riri",
            type: :alter_ego,
            code: "#{version}b",
            side_identifier: "B",
            is_primary_side: false
          }
        )
      end

      slot_card =
        create(Sanctum.Games.Card,
          attrs: %{base_code: "91004", code: "91004", set: "test_ironheart"}
        )

      create(Sanctum.Games.CardSide,
        attrs: %{card_id: slot_card.id, code: "91004", side_identifier: "A", type: :upgrade}
      )

      import_deck = fn id, hero_code ->
        assert {:ok, deck} =
                 MarvelCdb.import_decklist(%{
                   "id" => id,
                   "name" => "Deck on #{hero_code}",
                   "hero_code" => hero_code,
                   "slots" => %{"91004" => 2}
                 })

        deck
      end

      deck_v1 = import_deck.(90_001, "91001a")
      deck_v3 = import_deck.(90_002, "91003a")

      assert deck_v1.hero_id == deck_v3.hero_id

      hero = Ash.get!(Sanctum.Heroes.Hero, deck_v1.hero_id, authorize?: false)
      assert hero.base_code == "91001"
    end
  end

  defp seed_like_catalog do
    hero_card = create(Sanctum.Games.Card, attrs: %{base_code: "43001", code: "43001"})

    for {code, type, primary?, id} <- [
          {"43001a", :hero, true, "A"},
          {"43001b", :alter_ego, false, "B"}
        ] do
      create(Sanctum.Games.CardSide,
        attrs: %{
          card_id: hero_card.id,
          name: "Like Hero",
          type: type,
          code: code,
          side_identifier: id,
          is_primary_side: primary?
        }
      )
    end

    slot_card = create(Sanctum.Games.Card, attrs: %{base_code: "43002", code: "43002"})

    create(Sanctum.Games.CardSide,
      attrs: %{card_id: slot_card.id, code: "43002", side_identifier: "A"}
    )
  end

  defp like_payload(extra) do
    Map.merge(
      %{
        "id" => 43_100,
        "name" => "Liked deck",
        "hero_code" => "43001a",
        "slots" => %{"43002" => 2}
      },
      extra
    )
  end

  defp reload(deck), do: Ash.get!(Sanctum.Decks.Deck, deck.id, authorize?: false)

  defp backdate_like_changed_at(deck) do
    import Ecto.Query

    {:ok, uuid} = Ecto.UUID.dump(deck.id)

    Sanctum.Repo.update_all(from(d in "decks", where: d.id == ^uuid),
      set: [mcdb_like_changed_at: ~U[2024-01-01 00:00:00Z]]
    )
  end

  describe "helper functions" do
    test "extract_base_code/1" do
      assert MarvelCdb.extract_base_code("01001a") == "01001"
      assert MarvelCdb.extract_base_code("01001b") == "01001"
      assert MarvelCdb.extract_base_code("01001") == "01001"
      assert MarvelCdb.extract_base_code("01123c") == "01123"
    end

    test "extract_side_identifier/1" do
      assert MarvelCdb.extract_side_identifier("01001a") == "a"
      assert MarvelCdb.extract_side_identifier("01001b") == "b"
      assert MarvelCdb.extract_side_identifier("01001") == "a"
      assert MarvelCdb.extract_side_identifier("01123c") == "c"
    end
  end

  @tag :external
  test "loads spider man hero" do
    assert {:ok, _card} = MarvelCdb.load_card("01001a")
  end
end
