defmodule Sanctum.ObservabilityTest do
  use ExUnit.Case, async: true

  alias Sanctum.Observability

  defp sample(name), do: Observability.traces_sampler(%{transaction_context: %{name: name}})

  describe "traces_sampler/1" do
    test "drops Oban plugin ticks" do
      assert sample("Elixir.Oban.Stager process") == 0.0
      assert sample("Elixir.Oban.Plugins.Cron process") == 0.0
      assert sample("Elixir.Oban.Plugins.Pruner process") == 0.0
    end

    test "drops orphan repo query roots" do
      assert sample("sanctum.repo.query:oban_jobs") == 0.0
      assert sample("sanctum.repo.query:decks") == 0.0
      assert sample("sanctum.repo.query") == 0.0
    end

    test "samples real traffic at 100%" do
      assert sample("GET /games/:id") == 1.0
      # opentelemetry_oban names job spans "process <queue>"
      assert sample("process default") == 1.0
      assert sample("SanctumWeb.GameLive.Show.mount") == 1.0
    end

    test "handles non-binary span names (opentelemetry_bandit uses atoms)" do
      assert sample(:GET) == 1.0
      assert sample(:HTTP) == 1.0
      assert sample(~c"sanctum.repo.query:oban_jobs") == 0.0
    end
  end
end
