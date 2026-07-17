defmodule Sanctum.Search.ValueCacheTest do
  @moduledoc false

  # persistent_term is node-global state (and reset/0 clears every key), so
  # these tests stay synchronous.
  use ExUnit.Case, async: false

  alias Sanctum.Search.ValueCache

  setup do
    ValueCache.reset()
    on_exit(&ValueCache.reset/0)
  end

  test "computes once and serves from cache within the TTL" do
    counter = :counters.new(1, [])

    loader = fn ->
      :counters.add(counter, 1, 1)
      ["a", "b"]
    end

    assert ValueCache.fetch(:test_key, loader) == ["a", "b"]
    assert ValueCache.fetch(:test_key, loader) == ["a", "b"]
    assert :counters.get(counter, 1) == 1
  end

  test "recomputes after the TTL expires" do
    counter = :counters.new(1, [])

    loader = fn ->
      :counters.add(counter, 1, 1)
      ["v"]
    end

    assert ValueCache.fetch(:test_ttl, loader, ttl: 0) == ["v"]
    assert ValueCache.fetch(:test_ttl, loader, ttl: 0) == ["v"]
    assert :counters.get(counter, 1) == 2
  end

  test "reset clears cached entries" do
    assert ValueCache.fetch(:test_reset, fn -> ["old"] end) == ["old"]
    ValueCache.reset()
    assert ValueCache.fetch(:test_reset, fn -> ["new"] end) == ["new"]
  end

  test "a raising loader logs, returns [], and does not cache the failure" do
    import ExUnit.CaptureLog

    log =
      capture_log(fn ->
        assert ValueCache.fetch(:test_raise, fn -> raise "db down" end) == []
      end)

    assert log =~ "value cache loader"
    # The failure wasn't cached — a later healthy loader works.
    assert ValueCache.fetch(:test_raise, fn -> ["ok"] end) == ["ok"]
  end
end
