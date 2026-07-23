import Config

# LiveView pages load their data in start_async, and `render_async/1` waits up
# to :assert_receive_timeout (ExUnit default 100ms) for it. The heavier pages
# (e.g. the deck detail's nested load + similarity query) can exceed that on a
# cold CI runner, so give async loads generous headroom.
config :ex_unit, assert_receive_timeout: 2000

# The pool card-count cache is node-global `:persistent_term`; a 0 TTL forces
# every fetch to recompute against the calling test's Ecto sandbox instead of
# leaking a count between `async: true` tests.
config :sanctum, Sanctum.Games.CardPoolCount, ttl: 0

config :sanctum, Oban, testing: :manual
config :sanctum, :marvel_cdb_req_options, plug: {Req.Test, Sanctum.MarvelCdb}
config :sanctum, token_signing_secret: "/oZ9ck2w3h4oPYA4x7ZebHnqCh1MKXIp"
config :sanctum, :deploy_notice_token, "test-deploy-notice-token"
config :bcrypt_elixir, log_rounds: 1
config :ash, policies: [show_policy_breakdowns?: true]

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :sanctum, Sanctum.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "sanctum_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :sanctum, SanctumWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "r6twl/k5iX61kat0T5NGGiBLyDLjrPl/bWxCdGF/ZvYveZAeqDd22krsvlKcXtIc",
  server: false

# In test we don't send emails
config :sanctum, Sanctum.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Spans only go to Sentry in prod; stop the OTLP exporter from retrying
# a nonexistent localhost collector.
config :opentelemetry, traces_exporter: :none

# The metrics telemetry handler is attached in every env; keep tests from
# buffering metrics in Sentry's TelemetryProcessor (nothing sends without a
# DSN, but there's no reason to accumulate them either).
config :sentry, enable_metrics: false
