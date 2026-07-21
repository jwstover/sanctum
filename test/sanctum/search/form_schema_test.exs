defmodule Sanctum.Search.FormSchemaTest do
  # controls/1 resolves values_fun vocabularies (traits/sets/packs) through
  # the node-global ValueCache, so this needs the sandbox and can't share the
  # cache with concurrent tests.
  use Sanctum.DataCase, async: false

  alias Sanctum.Search.{CardFields, DeckFields, Field, FormSchema, Registry, ValueCache}

  setup do
    ValueCache.reset()
    on_exit(&ValueCache.reset/0)
  end

  describe "control_for/1" do
    test "derives controls from field kind for opted-in fields" do
      assert FormSchema.control_for(Registry.lookup(CardFields, "aspect")) == :chips
      assert FormSchema.control_for(Registry.lookup(CardFields, "is")) == :checks
      assert FormSchema.control_for(Registry.lookup(CardFields, "unique")) == :tristate
      assert FormSchema.control_for(Registry.lookup(CardFields, "trait")) == :select
      assert FormSchema.control_for(Registry.lookup(CardFields, "cost")) == :number
      assert FormSchema.control_for(Registry.lookup(CardFields, "attack")) == :number
    end

    test "form metadata can override the derived control" do
      field = %Field{
        name: "mine",
        kind: :boolean,
        form: %{group: "Ownership", control: :toggle},
        build: fn _op, _value -> {:ok, true} end
      }

      assert FormSchema.control_for(field) == :toggle
    end

    test "fields without form metadata have no control" do
      assert FormSchema.control_for(Registry.lookup(CardFields, "name")) == nil
      assert FormSchema.control_for(Registry.lookup(CardFields, "text")) == nil
      assert FormSchema.control_for(Registry.lookup(CardFields, "ownership")) == nil
      assert FormSchema.control_for(Registry.lookup(DeckFields, "title")) == nil
      assert FormSchema.control_for(Registry.lookup(DeckFields, "card")) == nil
      assert FormSchema.control_for(nil) == nil
    end
  end

  describe "controls/1" do
    test "groups card fields in metadata order" do
      groups = CardFields |> FormSchema.controls() |> Enum.map(&elem(&1, 0))

      assert groups == ["Aspect", "Type", "Traits & Sets", "Resources", "Properties", "Stats"]
    end

    test "orders members within a group and carries options" do
      {"Properties", controls} =
        CardFields |> FormSchema.controls() |> List.keyfind!("Properties", 0)

      assert Enum.map(controls, & &1.name) == ["unique", "owned", "is"]

      is_control = Enum.find(controls, &(&1.name == "is"))
      assert is_control.control == :checks
      assert {"unique", "Unique"} in is_control.options
      assert is_control.label == "Card is…"
    end

    test "humanizes enum option labels" do
      {"Type", [type]} = CardFields |> FormSchema.controls() |> List.keyfind!("Type", 0)

      assert {"player_side_scheme", "Player Side Scheme"} in type.options
      assert {"ally", "Ally"} in type.options
    end

    test "number controls carry the field's operators and no options" do
      {"Stats", stats} = CardFields |> FormSchema.controls() |> List.keyfind!("Stats", 0)

      assert Enum.map(stats, & &1.name) |> List.first() == "cost"
      cost = Enum.find(stats, &(&1.name == "cost"))
      assert cost.control == :number
      assert cost.ops == [:eq, :neq, :lt, :gt, :lte, :gte]
      assert cost.options == []

      assert Enum.map(stats, & &1.name) ==
               ~w(cost attack thwart defense health recover threat escalation max_threat
                  stage boost hand_size energy mental physical wild)
    end
  end

  describe "humanize/1" do
    test "title-cases underscore slugs" do
      assert FormSchema.humanize("player_side_scheme") == "Player Side Scheme"
      assert FormSchema.humanize("ally") == "Ally"
    end
  end
end
