defmodule Sanctum.Search.ParserTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Sanctum.Search.{Parser, Token}

  defp parse(input), do: Parser.parse(input)

  defp clause({:clause, c}), do: {c.field.value, c.op, Enum.map(c.values, & &1.value)}

  describe "clauses" do
    test "field = value" do
      {ast, []} = parse("aspect = aggression")
      assert clause(ast) == {"aspect", :eq, ["aggression"]}
    end

    test "colon and equals are interchangeable" do
      {a, []} = parse("cost:2")
      {b, []} = parse("cost=2")
      assert clause(a) == clause(b)
    end

    test "all comparison operators" do
      for {op_text, op} <- [
            {":", :eq},
            {"=", :eq},
            {"!=", :neq},
            {"!", :neq},
            {"<", :lt},
            {">", :gt},
            {"<=", :lte},
            {">=", :gte}
          ] do
        {ast, []} = parse("cost#{op_text}2")
        assert clause(ast) == {"cost", op, ["2"]}, "operator #{op_text}"
      end
    end

    test "quoted value" do
      {ast, []} = parse(~s(text:"draw a card"))
      assert clause(ast) == {"text", :eq, ["draw a card"]}
    end

    test "pipe-separated values" do
      {ast, []} = parse("aspect:justice|leadership|pool")
      assert clause(ast) == {"aspect", :eq, ["justice", "leadership", "pool"]}
    end
  end

  describe "boolean structure" do
    test "adjacent terms are an implicit AND" do
      {{:and, [a, b]}, []} = parse("aspect:justice cost<=2")
      assert clause(a) == {"aspect", :eq, ["justice"]}
      assert clause(b) == {"cost", :lte, ["2"]}
    end

    test "explicit AND keyword, case-insensitive" do
      {ast, []} = parse("aspect = aggression AND cost <= 2 AND type = ally")
      assert {:and, [a, b, c]} = ast
      assert clause(a) == {"aspect", :eq, ["aggression"]}
      assert clause(b) == {"cost", :lte, ["2"]}
      assert clause(c) == {"type", :eq, ["ally"]}
    end

    test "or groups lower than and" do
      {ast, []} = parse("type:ally cost:1 or type:event")
      assert {:or, [{:and, _}, _]} = ast
    end

    test "parentheses group" do
      {ast, []} = parse("(aspect:justice or aspect:pool) cost<3")
      assert {:and, [{:or, _}, _]} = ast
    end

    test "negation with hyphen and NOT keyword" do
      {{:not, a}, []} = parse("-type:ally")
      {{:not, b}, []} = parse("not type:ally")
      assert clause(a) == clause(b)
    end

    test "bare words" do
      {ast, []} = parse("spider-man")
      assert {:word, %Token{value: "spider-man"}} = ast
    end

    test "quoted phrase as bare term" do
      {ast, []} = parse(~s("peter parker"))
      assert {:word, %Token{value: "peter parker"}} = ast
    end

    test "bare word NOT at end of input stays a word" do
      {ast, []} = parse("not")
      assert {:word, %Token{value: "not"}} = ast
    end
  end

  describe "error tolerance" do
    test "trailing operator drops the clause, keeps the rest" do
      {ast, [diag]} = parse("type:ally cost <")
      assert clause(ast) == {"type", :eq, ["ally"]}
      assert diag.code == :incomplete_clause
    end

    test "stray closing paren is skipped" do
      {ast, [diag]} = parse("type:ally)")
      assert clause(ast) == {"type", :eq, ["ally"]}
      assert diag.code == :stray_token
    end

    test "unclosed paren still parses the group" do
      {ast, [diag]} = parse("(type:ally cost:1")
      assert {:and, [_, _]} = ast
      assert diag.code == :unclosed_paren
    end

    test "leading operator is skipped" do
      {ast, [diag]} = parse("<= 2 type:ally")
      assert diag.code == :stray_token
      # "2" becomes a bare word, type:ally still parses
      assert {:and, [{:word, %Token{value: "2"}}, _]} = ast
    end

    test "empty input" do
      assert {nil, []} = parse("")
      assert {nil, []} = parse("   ")
    end

    test "unterminated quote takes the rest of the input" do
      {ast, []} = parse(~s(text:"draw a))
      assert clause(ast) == {"text", :eq, ["draw a"]}
    end

    test "trailing pipe keeps parsed values" do
      {ast, [diag]} = parse("aspect:justice|")
      assert clause(ast) == {"aspect", :eq, ["justice"]}
      assert diag.code == :stray_token
    end
  end

  describe "spans" do
    test "tokens carry byte offsets into the input" do
      {ast, []} = parse("cost <= 2")
      {:clause, c} = ast
      assert c.field.start == 0
      assert c.field.length == 4
      assert c.op_token.start == 5
      assert [%Token{start: 8, length: 1}] = c.values
    end
  end
end
