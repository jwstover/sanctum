defmodule Sanctum.Observability do
  @moduledoc """
  Sentry hooks: trace sampling (`traces_sampler/1`) and custom metrics.

  Domain code stays Sentry-agnostic by emitting `:telemetry` events (either
  directly or through the small emit helpers here); `handle_metric_event/4`
  is the single place that translates them into `Sentry.Metrics` calls.
  Attached at boot via `attach_metrics_handlers/0`.
  """

  @metric_events [
    [:sanctum, :deck_sync, :run, :stop],
    [:sanctum, :deck_sync, :empty_day],
    [:sanctum, :marvel_cdb, :request, :stop],
    [:sanctum, :card_sync, :run, :stop],
    [:sanctum, :uniqueness, :recompute, :stop],
    [:sanctum, :deck, :user_import],
    [:sanctum, :game, :created],
    [:sanctum, :game, :action],
    [:sanctum, :auth, :sign_in],
    [:sanctum, :sessions, :active]
  ]

  @doc """
  Attaches the Sentry-metrics forwarder for all `@metric_events`. Idempotent
  per handler id; called once from `Sanctum.Application.start/2`. Safe in
  every env — without a DSN (dev) Sentry sends nothing, and test disables
  metrics via `:enable_metrics`.
  """
  def attach_metrics_handlers do
    :telemetry.attach_many(
      "sanctum-sentry-metrics",
      @metric_events,
      &__MODULE__.handle_metric_event/4,
      :ok
    )
  end

  ## Emit helpers (for call sites where an inline :telemetry.execute would
  ## drown the surrounding code, i.e. LiveView event handlers).

  @doc "Counts a created game."
  def game_created do
    :telemetry.execute([:sanctum, :game, :created], %{count: 1}, %{})
  end

  @doc """
  Counts a discrete in-game user action (`:draw`, `:move`, `:flip_card`, …).
  `count` is the batch size (cards drawn/dealt), so sums stay meaningful.
  """
  def game_action(action, count \\ 1) when is_atom(action) do
    :telemetry.execute([:sanctum, :game, :action], %{count: count}, %{action: action})
  end

  @doc "Counts a successful sign-in (AshAuthentication `activity` tuple)."
  def auth_success(activity) do
    :telemetry.execute(
      [:sanctum, :auth, :sign_in],
      %{count: 1},
      %{result: :success, activity: activity, reason: nil}
    )
  end

  @doc "Counts a failed sign-in with a compact `reason` tag."
  def auth_failure(activity, reason) do
    :telemetry.execute(
      [:sanctum, :auth, :sign_in],
      %{count: 1},
      %{result: :failure, activity: activity, reason: reason}
    )
  end

  ## Telemetry -> Sentry.Metrics

  @doc false
  def handle_metric_event([:sanctum, :deck_sync, :run, :stop], m, meta, :ok) do
    Sentry.Metrics.distribution("deck_sync.run.duration", m.duration_ms, unit: "millisecond")
    count_nonzero("deck_sync.days_processed", m.processed, "day")
    count_nonzero("deck_sync.decks_imported", m.imported, "deck")
    count_nonzero("deck_sync.decks_failed", m.failed, "deck")

    case meta.halted do
      %{date: date, reason: reason} ->
        Sentry.Metrics.count("deck_sync.halted", 1,
          attributes: %{date: to_string(date), reason: safe_string(reason)}
        )

      nil ->
        :ok
    end
  end

  def handle_metric_event([:sanctum, :deck_sync, :empty_day], m, meta, :ok) do
    Sentry.Metrics.count("deck_sync.empty_day_reclassified", m.count,
      attributes: %{date: to_string(meta.date), status: to_string(meta.status)}
    )
  end

  def handle_metric_event([:sanctum, :marvel_cdb, :request, :stop], m, meta, :ok) do
    endpoint = to_string(meta.endpoint)

    Sentry.Metrics.count("marvelcdb.request", 1,
      attributes: %{
        endpoint: endpoint,
        status: to_string(meta.status),
        status_class: status_class(meta.status)
      }
    )

    Sentry.Metrics.distribution("marvelcdb.request.duration", m.duration_ms,
      unit: "millisecond",
      attributes: %{endpoint: endpoint}
    )
  end

  def handle_metric_event([:sanctum, :card_sync, :run, :stop], m, meta, :ok) do
    Sentry.Metrics.distribution("card_sync.run.duration", m.duration_ms,
      unit: "millisecond",
      attributes: %{status: to_string(meta.status)}
    )

    count_nonzero("card_sync.cards_synced", m.synced, "card")
    count_nonzero("card_sync.cards_failed", m.data_failed, "card")
    count_nonzero("card_sync.images_uploaded", m.uploaded, "image")
    count_nonzero("card_sync.images_skipped", m.skipped, "image")
    count_nonzero("card_sync.images_failed", m.images_failed, "image")
  end

  def handle_metric_event([:sanctum, :uniqueness, :recompute, :stop], m, _meta, :ok) do
    Sentry.Metrics.distribution("uniqueness.recompute.duration", m.duration_ms,
      unit: "millisecond"
    )

    Sentry.Metrics.gauge("uniqueness.decks", m.decks, unit: "deck")
    Sentry.Metrics.gauge("uniqueness.decks_ranked", m.ranked, unit: "deck")
  end

  def handle_metric_event([:sanctum, :deck, :user_import], m, meta, :ok) do
    Sentry.Metrics.count("deck.user_import", m.count,
      attributes: %{result: to_string(meta.result), mcdb_type: to_string(meta.mcdb_type)}
    )
  end

  def handle_metric_event([:sanctum, :game, :created], m, _meta, :ok) do
    Sentry.Metrics.count("game.created", m.count, unit: "game")
  end

  def handle_metric_event([:sanctum, :game, :action], m, meta, :ok) do
    Sentry.Metrics.count("game.action", m.count, attributes: %{action: to_string(meta.action)})
  end

  # Zero is meaningful for this gauge (nobody online), so it is always emitted.
  def handle_metric_event([:sanctum, :sessions, :active], m, _meta, :ok) do
    Sentry.Metrics.gauge("sessions.active", m.count, unit: "session")
  end

  def handle_metric_event([:sanctum, :auth, :sign_in], m, meta, :ok) do
    attributes = %{result: to_string(meta.result), activity: safe_string(meta.activity)}

    attributes =
      if meta.reason, do: Map.put(attributes, :reason, to_string(meta.reason)), else: attributes

    Sentry.Metrics.count("auth.sign_in", m.count, attributes: attributes)
  end

  # A zero-valued counter is pure noise (counters aggregate by sum) — only the
  # nonzero occurrences carry signal, and absence reads correctly as zero.
  defp count_nonzero(_name, 0, _unit), do: :ok
  defp count_nonzero(name, value, unit), do: Sentry.Metrics.count(name, value, unit: unit)

  defp status_class(status) when is_integer(status), do: "#{div(status, 100)}xx"
  defp status_class(_other), do: "error"

  defp safe_string(value) when is_binary(value), do: value
  defp safe_string(value) when is_atom(value), do: to_string(value)
  defp safe_string(value), do: inspect(value)

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
    * LiveView longpoll transport requests (`/live/longpoll`) — fallback-
      transport polling fires every few seconds per client and each poll is
      its own root trace. Matched via the root span's `url.path` attribute,
      since opentelemetry_bandit names the span before routing (just `:GET`).

  Everything else (HTTP requests, LiveView, Oban jobs) is sampled at 100%.
  """
  def traces_sampler(%{transaction_context: %{name: name} = transaction_context}) do
    # OTel span names are chardata, not necessarily binaries — e.g.
    # opentelemetry_bandit names HTTP request spans with atoms (:GET, :HTTP).
    # A crash here is worse than it looks: Sentry rescues sampler errors and
    # samples the span at 0.0, silently dropping the trace.
    name = to_string(name)

    oban_plugin_tick? =
      String.starts_with?(name, "Elixir.Oban.") and String.ends_with?(name, " process")

    orphan_query? = String.starts_with?(name, "sanctum.repo.query")

    if oban_plugin_tick? or orphan_query? or longpoll?(transaction_context), do: 0.0, else: 1.0
  end

  defp longpoll?(%{attributes: %{:"url.path" => path}}) when is_binary(path) do
    String.starts_with?(path, "/live/longpoll")
  end

  defp longpoll?(_transaction_context), do: false
end
