defmodule Sanctum.Search.FormSyncTest do
  use ExUnit.Case, async: true

  alias Sanctum.Search.{CardFields, Field, FormSync}

  # A registry with a static vocabulary so :select behavior is testable
  # without the database-backed values_fun in Values.
  defmodule VocabFields do
    @behaviour Sanctum.Search.Registry

    @impl true
    def bare_word(_value), do: true

    @impl true
    def fields do
      [
        %Field{
          name: "hero",
          aliases: ["h"],
          kind: :text,
          values_fun: fn -> ["Black Panther (T'Challa)", "Spider-Man", "Groot"] end,
          form: %{group: "Hero", order: 10},
          build: fn _op, _value -> {:ok, true} end
        },
        %Field{
          name: "mine",
          kind: :boolean,
          values: ["true", "false"],
          form: %{group: "Ownership", order: 20, control: :toggle},
          build: fn _op, _value -> {:ok, true} end
        }
      ]
    end
  end

  describe "read/2" do
    test "empty query has no fields and no residual" do
      assert %{fields: fields, residual: ""} = FormSync.read("", CardFields)
      assert fields == %{}
    end

    test "adopts enum clauses as chips values" do
      assert %{fields: %{"type" => ["ally"]}} = FormSync.read("t:ally", CardFields)
    end

    test "adopts value-OR alternatives as a multi-select" do
      assert %{fields: %{"aspect" => ["justice", "aggression"]}} =
               FormSync.read("aspect:justice|aggression", CardFields)
    end

    test "adopts each single-value is: flag clause" do
      assert %{fields: %{"is" => ["unique", "crisis"]}} =
               FormSync.read("is:unique is:crisis", CardFields)
    end

    test "value-OR on flags is residual (OR semantics don't fit checkboxes)" do
      assert %{fields: fields, residual: "is:unique|crisis"} =
               FormSync.read("is:unique|crisis", CardFields)

      assert fields == %{}
    end

    test "adopts boolean clauses with true/false literals only" do
      assert %{fields: %{"unique" => "true"}} = FormSync.read("unique:true", CardFields)
      assert %{fields: fields, residual: "u:yes"} = FormSync.read("u:yes", CardFields)
      assert fields == %{}
    end

    test "adopts numeric clauses with any supported operator" do
      assert %{fields: %{"cost" => %{op: :lte, value: "2"}}} =
               FormSync.read("cost<=2", CardFields)

      assert %{fields: %{"cost" => %{op: :eq, value: "x"}}} =
               FormSync.read("cost:x", CardFields)
    end

    test "numeric values the field's build rejects are residual" do
      # X only supports : and != — a bound comparison is invalid
      assert %{fields: fields, residual: "cost<x"} = FormSync.read("cost<x", CardFields)
      assert fields == %{}
    end

    test "adopts vocabulary selects using the vocabulary's spelling" do
      assert %{fields: %{"hero" => "Black Panther (T'Challa)"}} =
               FormSync.read(~s{hero:"black panther (t'challa)"}, VocabFields)
    end

    test "partial vocabulary matches are residual" do
      assert %{fields: fields, residual: "hero:spider"} =
               FormSync.read("hero:spider", VocabFields)

      assert fields == %{}
    end

    test "negated clauses are residual" do
      assert %{fields: fields, residual: "-t:ally"} = FormSync.read("-t:ally", CardFields)
      assert fields == %{}
    end

    test "parenthesized and OR-grouped clauses are residual" do
      input = "(a:justice or a:aggression) cost<=2"

      assert %{fields: %{"cost" => %{op: :lte, value: "2"}} = fields, residual: residual} =
               FormSync.read(input, CardFields)

      assert residual == "(a:justice or a:aggression)"
      refute Map.has_key?(fields, "aspect")
    end

    test "only the first clause per field is adopted" do
      assert %{fields: %{"type" => ["ally"]}, residual: "t:event"} =
               FormSync.read("t:ally t:event", CardFields)
    end

    test "invalid enum values are residual" do
      assert %{fields: fields, residual: "t:alyy"} = FormSync.read("t:alyy", CardFields)
      assert fields == %{}
    end

    test "non-eq operators on choice fields are residual" do
      assert %{fields: fields, residual: "a!=justice"} = FormSync.read("a!=justice", CardFields)
      assert fields == %{}
    end

    test "bare words and text clauses are residual" do
      assert %{fields: %{"type" => ["ally"]}, residual: residual} =
               FormSync.read(~s(spider name:"peter parker" t:ally), CardFields)

      assert residual == ~s(spider name:"peter parker")
    end
  end

  describe "update/3" do
    test "appends canonical clauses to an empty query" do
      assert FormSync.update("", CardFields, %{"type" => ["ally"]}) == "type:ally"
    end

    test "appends multi-value chips as value-OR" do
      assert FormSync.update("", CardFields, %{"aspect" => ["justice", "leadership"]}) ==
               "aspect:justice|leadership"
    end

    test "appends after existing residual text, preserving it byte-for-byte" do
      assert FormSync.update("spider -t:event", CardFields, %{"aspect" => ["justice"]}) ==
               "spider -t:event aspect:justice"
    end

    test "appends fields in registry order" do
      assert FormSync.update("", CardFields, %{
               "cost" => %{op: :lte, value: "2"},
               "aspect" => ["justice"],
               "type" => ["ally"]
             }) == "type:ally aspect:justice cost<=2"
    end

    test "edits a clause in place, preserving alias and operator spelling" do
      assert FormSync.update("a=justice cost:2", CardFields, %{
               "aspect" => ["justice", "leadership"]
             }) == "a=justice|leadership cost:2"
    end

    test "clearing a field deletes its clause" do
      assert FormSync.update("t:ally spider", CardFields, %{"type" => []}) == "spider"
      assert FormSync.update("spider t:ally", CardFields, %{"type" => []}) == "spider"
    end

    test "deleting a clause swallows an adjacent standalone and" do
      assert FormSync.update("t:ally and cost:2", CardFields, %{"type" => []}) == "cost:2"
      assert FormSync.update("cost:2 and t:ally", CardFields, %{"type" => []}) == "cost:2"
    end

    test "flags diff per value" do
      assert FormSync.update("is:unique is:crisis spider", CardFields, %{"is" => ["crisis"]}) ==
               "is:crisis spider"

      assert FormSync.update("is:crisis", CardFields, %{"is" => ["crisis", "hazard"]}) ==
               "is:crisis is:hazard"
    end

    test "numeric edits keep the original operator spelling when unchanged" do
      assert FormSync.update("cost=2", CardFields, %{"cost" => %{op: :eq, value: "4"}}) ==
               "cost=4"
    end

    test "numeric edits rewrite the operator when it changes" do
      assert FormSync.update("cost<=2", CardFields, %{"cost" => %{op: :gte, value: "3"}}) ==
               "cost>=3"
    end

    test "numeric ranges only manage the first clause" do
      assert %{fields: %{"cost" => %{op: :gte, value: "2"}}} =
               FormSync.read("cost>=2 cost<=4", CardFields)

      assert FormSync.update("cost>=2 cost<=4", CardFields, %{
               "cost" => %{op: :gte, value: "3"}
             }) == "cost>=3 cost<=4"
    end

    test "quotes values containing word-stop characters" do
      assert FormSync.update("", VocabFields, %{"hero" => "Black Panther (T'Challa)"}) ==
               ~s{hero:"Black Panther (T'Challa)"}
    end

    test "select values commit only on exact vocabulary matches" do
      # half-typed typeahead input: leave the query alone
      assert FormSync.update("t:ally", VocabFields, %{"hero" => "spid"}) == "t:ally"
      assert FormSync.update("hero:Groot", VocabFields, %{"hero" => "spid"}) == "hero:Groot"

      # a completed value commits with the vocabulary's spelling
      assert FormSync.update("", VocabFields, %{"hero" => "spider-man"}) == "hero:Spider-Man"

      # empty still clears
      assert FormSync.update("hero:Groot spider", VocabFields, %{"hero" => ""}) == "spider"
    end

    test "toggle fields render true and clear" do
      assert FormSync.update("", VocabFields, %{"mine" => "true"}) == "mine:true"
      assert FormSync.update("mine:true groot", VocabFields, %{"mine" => ""}) == "groot"
    end

    test "fields absent from the map are left untouched" do
      assert FormSync.update("t:ally cost<=2", CardFields, %{"aspect" => ["justice"]}) ==
               "t:ally cost<=2 aspect:justice"
    end

    test "an unchanged submit returns the input verbatim, whitespace included" do
      input = "  t:Ally   cost<=2 "
      %{fields: fields} = FormSync.read(input, CardFields)
      assert FormSync.update(input, CardFields, fields) == input
    end

    test "residual bytes survive any control change" do
      input = ~s{(a:justice or spider) -is:unique  name:"peter  parker" t:ally}

      updated = FormSync.update(input, CardFields, %{"type" => ["event"], "unique" => "true"})

      assert updated ==
               ~s{(a:justice or spider) -is:unique  name:"peter  parker" t:event unique:true}
    end

    test "read/update round-trip is stable" do
      for input <- [
            "t:ally",
            "aspect:justice|aggression is:unique cost<=2",
            "spider -t:event (a:justice or a:aggression)",
            ~s{hero:"Black Panther (T'Challa)"}
          ] do
        registry = if String.starts_with?(input, "hero"), do: VocabFields, else: CardFields
        %{fields: fields} = FormSync.read(input, registry)
        assert FormSync.update(input, registry, fields) == input

        rewritten = FormSync.update(input, registry, fields)
        assert FormSync.read(rewritten, registry).fields == fields
      end
    end
  end

  describe "active_count/2" do
    test "counts managed values and non-word residual conjuncts" do
      # type: 2 values, is: 1, cost: 1, -a:justice residual: 1, bare word: 0
      assert FormSync.active_count("t:ally|event is:unique cost<=2 -a:justice spider", CardFields) ==
               5
    end

    test "is zero for plain text search" do
      assert FormSync.active_count("spider man", CardFields) == 0
      assert FormSync.active_count("", CardFields) == 0
    end
  end

  describe "fields_from_params/2" do
    test "collects list, scalar, and numeric params for managed fields" do
      params = %{
        "type" => ["", "ally"],
        "unique" => "",
        "cost" => "2",
        "cost_op" => "lte",
        "_target" => ["type"],
        "bogus" => "x"
      }

      assert FormSync.fields_from_params(params, CardFields) == %{
               "type" => ["ally"],
               "unique" => "",
               "cost" => %{op: "lte", value: "2"}
             }
    end

    test "absent params stay absent" do
      assert FormSync.fields_from_params(%{"aspect" => ["justice"]}, CardFields) ==
               %{"aspect" => ["justice"]}
    end
  end
end
