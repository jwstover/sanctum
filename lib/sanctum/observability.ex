defmodule Sanctum.Observability do
  @moduledoc """
  Sentry tracing hooks. See `traces_sampler/1`.
  """

  @doc """
  Root-span sampling decision for Sentry tracing (`:traces_sampler` in
  config/prod.exs). Only called for spans that start a new trace — child spans
  inherit their root's decision.

  Drops the background noise that would otherwise flood the transaction quota
  (Oban's Stager ticks once per second; each orphan repo query becomes its own
  transaction):

    * Oban plugin ticks (`Elixir.Oban.Stager process`, Cron/Pruner/Lifeline) —
      dropping the root also drops the plugin's child query spans.
    * Bare `sanctum.repo.query:*` roots — queries with no surrounding trace
      (oban_met sampling, peer election, card/deck sync tasks). Queries inside
      request, LiveView, and Oban job traces are children and are unaffected.

  Everything else (HTTP requests, LiveView, Oban jobs) is sampled at 100%.
  """
  def traces_sampler(%{transaction_context: %{name: name}}) do
    oban_plugin_tick? =
      String.starts_with?(name, "Elixir.Oban.") and String.ends_with?(name, " process")

    orphan_query? = String.starts_with?(name, "sanctum.repo.query")

    if oban_plugin_tick? or orphan_query?, do: 0.0, else: 1.0
  end
end
