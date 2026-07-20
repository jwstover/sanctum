defmodule Sanctum.Search.SuggestTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Sanctum.Search.{CardFields, Suggest}

  defp suggest(input, cursor), do: Suggest.suggest(input, cursor, CardFields)

  defp labels(result), do: Enum.map(result.items, & &1.label)

  test "empty input suggests fields" do
    result = suggest("", 0)
    assert "name" in labels(result)
    assert result.start == 0 and result.length == 0
    assert Enum.all?(result.items, &(&1.kind == "field"))
  end

  test "partial field name filters and spans the word" do
    result = suggest("asp", 3)
    assert labels(result) == ["aspect"]
    assert %{start: 0, length: 3} = result
    assert hd(result.items).insert == "aspect:"
  end

  test "alias prefix surfaces the alias with its canonical name in the detail" do
    result = suggest("atk", 3)
    assert [%{label: "atk", detail: detail, insert: "atk:"}] = result.items
    assert detail =~ "attack"
  end

  test "after field colon suggests enum values" do
    result = suggest("aspect:", 7)
    assert "aggression" in labels(result)
    assert "hero" in labels(result)
    assert Enum.all?(result.items, &(&1.kind == "value"))
    assert %{start: 7, length: 0} = result
  end

  test "partial value filters and spans the value token" do
    result = suggest("aspect:agg", 10)
    assert labels(result) == ["aggression"]
    assert %{start: 7, length: 3} = result
  end

  test "cursor mid-word completes against the whole token" do
    result = suggest("aspect:agg cost<=2", 9)
    assert labels(result) == ["aggression"]
  end

  test "space after a complete clause starts a new field context" do
    result = suggest("aspect:justice ", 15)
    assert "cost" in labels(result)
  end

  test "value context survives a space after the operator" do
    result = suggest("aspect: ", 8)
    assert "justice" in labels(result)
  end

  test "text fields offer no value suggestions" do
    assert suggest("name:", 5).items == []
  end

  test "unknown field offers no value suggestions" do
    assert suggest("bogus:", 6).items == []
  end

  test "no suggestions inside a quoted phrase" do
    assert suggest(~s(text:"draw), 8).items == []
  end

  test "keywords complete once typing starts" do
    assert "or" in labels(suggest("t:ally o", 8))
  end

  test "is: suggests flags" do
    assert "unique" in labels(suggest("is:", 3))
    assert "owned" in labels(suggest("own", 3))
  end

  test "utf-16 offsets round-trip for non-BMP input" do
    # "𝕏" is a surrogate pair: 2 UTF-16 units, 4 bytes.
    result = suggest("𝕏 asp", 5)
    assert labels(result) == ["aspect"]
    assert %{start: 3, length: 3} = result
  end
end
