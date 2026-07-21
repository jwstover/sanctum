defmodule Sanctum.Search.CompilerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Sanctum.Search
  alias Sanctum.Search.{CardFields, DeckFields}

  defp compile(input, registry \\ CardFields), do: Search.compile(input, registry)

  defp codes(result), do: Enum.map(result.diagnostics, & &1.code)

  describe "card queries" do
    test "the flagship example compiles cleanly" do
      result = compile("aspect = aggression AND cost <= 2 AND type = ally")
      assert result.expr != nil
      assert result.diagnostics == []
    end

    test "shorthand aliases compile to the same filter as full names" do
      a = compile("a:aggression c<=2 t:ally")
      b = compile("aspect:aggression cost<=2 type:ally")
      assert inspect(a.expr) == inspect(b.expr)
      assert a.diagnostics == []
    end

    test "enum values accept unique prefixes" do
      assert compile("t:all").diagnostics == []
      assert compile("a:agg").diagnostics == []
    end

    test "aspect accepts ownership pools" do
      assert %{expr: expr, diagnostics: []} = compile("aspect:hero")
      assert inspect(expr) =~ "ownership"
    end

    test "stat fields compile to jsonb value fragments" do
      assert %{expr: expr, diagnostics: []} = compile("attack>=2")
      assert inspect(expr) =~ "value"
    end

    test "empty and whitespace input compile to no filter" do
      assert %{expr: nil, diagnostics: []} = compile("")
      assert %{expr: nil, diagnostics: []} = compile("   ")
    end

    test "bare word falls back to name search" do
      assert %{expr: expr, diagnostics: []} = compile("spider")
      assert inspect(expr) =~ "ilike"
    end

    test "unknown field drops the clause but keeps the rest" do
      result = compile("bogus:1 t:ally")
      assert result.expr != nil
      assert codes(result) == [:unknown_field]
      assert hd(result.diagnostics).message =~ ~s(unknown field "bogus")
    end

    test "unknown field alone yields no filter (results stay live)" do
      assert %{expr: nil} = compile("bogus:1")
    end

    test "invalid enum value matches nothing and suggests a fix" do
      result = compile("aspect:agression")
      assert result.expr == false
      assert codes(result) == [:invalid_value]
      assert hd(result.diagnostics).message =~ "aggression"
    end

    test "non-numeric value on a numeric field" do
      result = compile("cost:banana")
      assert result.expr == false
      assert codes(result) == [:invalid_value]
    end

    test "x matches a printed X on cost and stat fields" do
      assert %{expr: expr, diagnostics: []} = compile("cost:x")
      assert inspect(expr) =~ "-1"

      assert %{expr: expr, diagnostics: []} = compile("attack!=X")
      assert inspect(expr) =~ "-1"
    end

    test "x rejects numeric bounds" do
      result = compile("cost<x")
      assert result.expr == false
      assert codes(result) == [:invalid_value]
    end

    test "unsupported operator on a field" do
      result = compile("aspect>2")
      assert result.expr == nil
      assert codes(result) == [:unsupported_operator]
    end

    test "incomplete trailing clause keeps the valid prefix" do
      result = compile("t:ally cost <")
      assert result.expr != nil
      assert codes(result) == [:incomplete_clause]
    end

    test "pipe values OR for eq and AND for neq" do
      eq = compile("aspect:justice|leadership")
      neq = compile("aspect!=justice|leadership")
      assert inspect(eq.expr) =~ " or "
      assert inspect(neq.expr) =~ " and "
    end

    test "negation wraps in not" do
      assert inspect(compile("-t:ally").expr) =~ "not"
    end

    test "is: flags" do
      assert %{diagnostics: []} = compile("is:unique")
      assert %{diagnostics: []} = compile("is:crisis")
      result = compile("is:sparkly")
      assert result.expr == false
      assert codes(result) == [:invalid_value]
    end

    test "every registered example compiles without diagnostics" do
      for field <- CardFields.fields(), field.example do
        result = compile(field.example)
        assert result.diagnostics == [], "example #{field.example} produced diagnostics"
        assert result.expr != nil
      end
    end
  end

  describe "deck queries" do
    test "hero + aspect + card count" do
      result = compile(~s(hero:spider aspect:justice cards>=40), DeckFields)
      assert result.expr != nil
      assert result.diagnostics == []
    end

    test "basic decks filter on empty aspect array" do
      assert %{expr: expr, diagnostics: []} = compile("aspect:basic", DeckFields)
      assert inspect(expr) =~ "cardinality"
    end

    test "deck containment search" do
      assert %{expr: expr, diagnostics: []} = compile(~s(card:"boot camp"), DeckFields)
      assert inspect(expr) =~ "exists"
    end

    test "every registered example compiles without diagnostics" do
      for field <- DeckFields.fields(), field.example do
        result = compile(field.example, DeckFields)
        assert result.diagnostics == [], "example #{field.example} produced diagnostics"
        assert result.expr != nil
      end
    end
  end

  describe "ILIKE pattern safety" do
    test "wildcards in user input are escaped" do
      result = compile("name:100%")
      assert inspect(result.expr) =~ ~S(\\%)
    end
  end
end
