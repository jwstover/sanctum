defmodule Sanctum.Search.GlobalTest do
  @moduledoc """
  The site-wide search: `in:` scope extraction, strict per-type applicability,
  remainder serialization (pure), and the fan-out through real Ash queries
  (DB-backed).
  """

  use Sanctum.DataCase, async: true

  import Sanctum.Factory

  alias Sanctum.Search.{CardFields, DeckFields, Global, HeroFields, Parser}

  # -- scope extraction (pure) -------------------------------------------------

  describe "extract_scope/1" do
    defp extract(input) do
      {ast, _diags} = Parser.parse(input)
      Global.extract_scope(ast)
    end

    test "no in: clause leaves scope :all and the AST untouched" do
      {scope, ast, spans, diags} = extract("spider cost<=2")

      assert scope == :all
      assert {:and, [_, _]} = ast
      assert spans == []
      assert diags == []
    end

    test "extracts a single type" do
      {scope, ast, spans, diags} = extract("in:cards spider")

      assert scope == MapSet.new([:cards])
      assert {:word, _} = ast
      assert [{0, 8}] = spans
      assert diags == []
    end

    test "singular aliases and pipe values combine" do
      {scope, _ast, _spans, []} = extract("in:card|decks spider")

      assert scope == MapSet.new([:cards, :decks])
    end

    test "a lone in: clause leaves a nil remainder" do
      {scope, ast, _spans, []} = extract("in:decks")

      assert scope == MapSet.new([:decks])
      assert ast == nil
    end

    test "unknown type value warns and falls back to :all" do
      {scope, _ast, _spans, [diag]} = extract("in:foo spider")

      assert scope == :all
      assert diag.code == :unknown_type
      assert diag.message =~ ~s("foo" isn't a searchable type)
    end

    test "in: nested under or/not is dropped with a diagnostic" do
      {scope, ast, spans, [diag]} = extract("spider or in:cards web")

      assert scope == :all
      assert diag.code == :misplaced_scope
      # the in: clause is gone from the AST but both words survive
      assert {:or, [{:word, _}, {:word, _}]} = ast
      assert length(spans) == 1
    end
  end

  # -- per-type applicability (pure) --------------------------------------------

  describe "applicable?/2" do
    defp applicable?(input, registry) do
      {ast, _} = Parser.parse(input)
      Global.applicable?(ast, registry)
    end

    test "bare words apply to every registry" do
      assert applicable?("spider", CardFields)
      assert applicable?("spider", DeckFields)
      assert applicable?("spider", HeroFields)
    end

    test "a field unknown to a registry excludes it" do
      assert applicable?("cost<=2", CardFields)
      refute applicable?("cost<=2", DeckFields)
      refute applicable?("cost<=2", HeroFields)
    end

    test "a shared field applies to every registry that knows it" do
      assert applicable?("aspect:aggression", CardFields)
      assert applicable?("aspect:aggression", DeckFields)
      refute applicable?("aspect:aggression", HeroFields)
    end

    test "value-level mismatch excludes the type" do
      # "hero" is a valid card aspect-pool but not a deck aspect
      assert applicable?("aspect:hero", CardFields)
      refute applicable?("aspect:hero", DeckFields)
    end

    test "one valid alternative among piped values is enough" do
      assert applicable?("aspect:hero|justice", DeckFields)
    end

    test "unsupported operator excludes the type" do
      refute applicable?("title>2", DeckFields)
    end

    test "any foreign clause under and/or/not excludes the type" do
      refute applicable?("spider or cost<=2", DeckFields)
      refute applicable?("-cost<=2 spider", DeckFields)
    end
  end

  # -- remainder serialization (pure) --------------------------------------------

  describe "remainder/2" do
    defp remainder_of(input) do
      {ast, _} = Parser.parse(input)
      {_scope, _ast, spans, _diags} = Global.extract_scope(ast)
      Global.remainder(input, spans)
    end

    test "strips the in: clause and its surrounding whitespace" do
      assert remainder_of("in:cards cost<=2") == "cost<=2"
      assert remainder_of("cost<=2 in:cards") == "cost<=2"
      assert remainder_of("spider in:cards cost<=2") == "spider cost<=2"
    end

    test "keeps quoted whitespace intact" do
      assert remainder_of(~s(in:cards name:"foo  bar")) == ~s(name:"foo  bar")
    end

    test "a lone in: clause leaves an empty remainder" do
      assert remainder_of("in:decks") == ""
    end

    test "no spans returns the trimmed input" do
      assert remainder_of("  spider  ") == "spider"
    end
  end

  # -- global autocomplete (pure) --------------------------------------------------

  describe "suggest/2" do
    defp labels(input) do
      %{items: items} = Global.suggest(input, String.length(input))
      Enum.map(items, & &1.label)
    end

    test "offers in: alongside the union of type fields" do
      %{items: items} = Global.suggest("", 0)
      all_labels = Enum.map(items, & &1.label)

      assert "in" in all_labels
      # card fields lead (registry order = priority)
      assert "name" in all_labels
    end

    test "completes in: values with the type keys" do
      assert labels("in:") == Global.type_values()
      assert labels("in:vil") == ["villains"]
    end

    test "union covers fields from every registry, deduplicated" do
      assert labels("tit") == ["title"]
      assert labels("set_t") == ["set_type"]
      assert Enum.count(labels("na"), &(&1 == "name")) == 1
    end

    test "ambiguous fields say which types they cover" do
      %{items: [title]} = Global.suggest("tit", 3)
      assert title.detail =~ "decks"
    end

    test "scoping to one type delegates to that registry" do
      # "title" is a deck field; scoped to cards it should vanish
      assert "title" in labels("tit")
      assert labels("in:cards tit") == []
      assert "cost" in labels("in:cards co")
    end
  end

  # -- fan-out (DB-backed) --------------------------------------------------------

  describe "search/3" do
    # A marker string no factory-generated name will collide with.
    @marker "Zzyzx"

    defp insert_side(attrs) do
      pack =
        create(Sanctum.Catalog.Pack,
          action: :upsert_from_marvelcdb,
          attrs: %{code: "zz_pack", name: "Zzyzx Pack"}
        )

      card = create(Sanctum.Games.Card, attrs: %{pack_id: pack.id, pack: pack.code})

      create(Sanctum.Games.CardSide,
        attrs:
          Map.merge(
            %{card_id: card.id, code: card.code, side_identifier: "A", is_primary_side: true},
            attrs
          )
      )
    end

    defp insert_hero(attrs) do
      hero_card = create(Sanctum.Games.Card, attrs: %{})

      create(Sanctum.Games.CardSide,
        attrs: %{
          card_id: hero_card.id,
          name: attrs[:hero_name],
          type: :hero,
          code: hero_card.code,
          side_identifier: "A",
          is_primary_side: true
        }
      )

      alter_ego_card = create(Sanctum.Games.Card, attrs: %{base_code: hero_card.base_code})

      create(Sanctum.Games.CardSide,
        attrs: %{
          card_id: alter_ego_card.id,
          name: attrs[:alter_ego_name],
          type: :alter_ego,
          code: alter_ego_card.code,
          side_identifier: "B",
          is_primary_side: true
        }
      )

      {:ok, hero} =
        Sanctum.Heroes.find_or_create_hero(
          Map.merge(%{base_code: hero_card.base_code, card_id: hero_card.id}, attrs)
        )

      hero
    end

    defp insert_deck(attrs) do
      Sanctum.Decks.Deck
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create!(authorize?: false)
    end

    defp insert_villain(attrs) do
      Sanctum.Villains.Villain
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create!(authorize?: false)
    end

    defp insert_card_set(attrs) do
      Sanctum.Catalog.CardSet
      |> Ash.Changeset.for_create(:upsert, attrs)
      |> Ash.create!(authorize?: false)
    end

    defp group_types(%{groups: groups}), do: Enum.map(groups, & &1.type)

    defp group(result, type), do: Enum.find(result.groups, &(&1.type == type))

    setup do
      insert_side(%{name: "#{@marker} Blade", type: :ally, cost: 2, aspect: :aggression})

      hero = insert_hero(%{hero_name: "#{@marker} Man", alter_ego_name: "Zed", set: "zz_hero"})
      insert_deck(%{title: "#{@marker} Deck", hero_id: hero.id, aspects: [:aggression]})

      pack =
        create(Sanctum.Catalog.Pack,
          action: :upsert_from_marvelcdb,
          attrs: %{code: "zzp", name: "#{@marker} Rising"}
        )

      insert_card_set(%{
        code: "zz_villain",
        name: "#{@marker} Set",
        set_type: :villain,
        pack_id: pack.id
      })

      insert_villain(%{villain_name: "#{@marker} Prime", set: "zz_villain"})
      create(Sanctum.Games.Scenario, attrs: %{name: "#{@marker} Scenario", set: "zz_villain"})

      %{pack: pack}
    end

    test "a bare word fans out across every type in fixed order" do
      result = Global.search(@marker, nil)

      assert group_types(result) == [
               :cards,
               :decks,
               :heroes,
               :packs,
               :card_sets,
               :villains,
               :scenarios
             ]

      assert result.diagnostics == []
    end

    test "result shapes link to the right destinations", %{pack: pack} do
      result = Global.search(@marker, nil)

      # the hero's identity side also matches the marker, so pick out the ally
      card = Enum.find(group(result, :cards).results, &(&1.title == "#{@marker} Blade"))
      assert card.href == "/cards/#{card.id}"
      assert card.subtitle == "Ally · #{@marker} Pack"

      [deck] = group(result, :decks).results
      assert deck.title == "#{@marker} Deck"
      assert deck.subtitle == "#{@marker} Man"
      assert deck.href == "/decks/#{deck.id}"

      [hero] = group(result, :heroes).results
      assert hero.href == "/decks?hero_id=#{hero.id}"

      found_pack = Enum.find(group(result, :packs).results, &(&1.title == "#{@marker} Rising"))
      assert found_pack.href == "/browse/#{pack.code}"

      # villain + scenario resolve their set slug to the pack's browse page
      [villain] = group(result, :villains).results
      assert villain.href == "/browse/#{pack.code}"

      [scenario] = group(result, :scenarios).results
      assert scenario.href == "/browse/#{pack.code}"
    end

    test "typed clauses implicitly narrow to the types that understand them" do
      assert group_types(Global.search("#{@marker} cost<=2", nil)) == [:cards]

      assert group_types(Global.search("#{@marker} aspect:aggression", nil)) == [
               :cards,
               :decks
             ]
    end

    test "in: scopes explicitly and raises the per-type limit" do
      result = Global.search("in:villains #{@marker}", nil)

      assert group_types(result) == [:villains]
    end

    test "unmatched villain set degrades to a link-less result" do
      insert_villain(%{villain_name: "#{@marker} Ghost", set: "no_such_set"})

      villains = group(Global.search("in:villains #{@marker}", nil), :villains)
      ghost = Enum.find(villains.results, &(&1.title == "#{@marker} Ghost"))

      assert ghost.href == nil
    end

    test "more?/more_url carry the in:-stripped remainder for cards and decks" do
      for n <- 1..6 do
        insert_side(%{name: "#{@marker} Extra #{n}", type: :ally, cost: 1})
      end

      result = Global.search("in:cards #{@marker} cost<=2", nil, limit: 5)
      cards = group(result, :cards)

      assert cards.more?
      assert length(cards.results) == 5
      assert cards.more_url == "/cards?query=#{URI.encode_www_form("#{@marker} cost<=2")}"
    end

    test "groups with no matches are omitted" do
      result = Global.search("#{@marker} Blade", nil)

      assert group_types(result) == [:cards]
    end

    test "empty and unusable input return no groups" do
      assert Global.search("", nil).groups == []
      assert Global.search("   ", nil).groups == []

      # nothing usable and no scope: don't list the catalog
      result = Global.search("cost<", nil)
      assert result.groups == []
      assert Enum.any?(result.diagnostics, &(&1.code == :incomplete_clause))
    end
  end
end
