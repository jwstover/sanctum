# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ash_oban, pro?: false

config :sanctum, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 10],
  repo: Sanctum.Repo,
  plugins: [
    # Prune old completed/discarded jobs so the table doesn't grow unbounded.
    Oban.Plugins.Pruner,
    # Backstop for jobs orphaned in the `executing` state. The fast path is
    # `Sanctum.Oban.BootRescue`, which resets a machine's own orphans when it
    # boots; Lifeline covers what BootRescue can't — a machine that is
    # destroyed and never boots again, or a node that stays up but somehow
    # dropped a job. `rescue_after` stays high so it never clobbers a genuinely
    # long-running job (it rescues purely on elapsed time, not liveness).
    {Oban.Plugins.Lifeline, rescue_after: :timer.hours(24)},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", Sanctum.Decks.DecklistSyncWorker},
       {"30 4 * * *", Sanctum.Decks.ComputeUniquenessWorker}
     ]}
  ]

config :ash,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :admin,
        :authentication,
        :tokens,
        :postgres,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [
      section_order: [:admin, :resources, :policies, :authorization, :domain, :execution]
    ]
  ]

config :sanctum,
  env: config_env(),
  ecto_repos: [Sanctum.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [
    Sanctum.Accounts,
    Sanctum.Catalog,
    Sanctum.Collections,
    Sanctum.Decks,
    Sanctum.Events,
    Sanctum.Games,
    Sanctum.Heroes,
    Sanctum.Homebrew,
    Sanctum.Villains
  ]

# Public base URL of the bucket that mirrors MarvelCDB card scans (see
# `mix sanctum.sync_cards`). Dev and prod share the same public bucket.
config :sanctum, :card_image_base_url, "https://sanctum-cards.fly.storage.tigris.dev"

# Extra Req options merged into every MarvelCDB request; test.exs uses this
# to route requests to a Req.Test stub.
config :sanctum, :marvel_cdb_req_options, []

# Configures the endpoint
config :sanctum, SanctumWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SanctumWeb.ErrorHTML, json: SanctumWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Sanctum.PubSub,
  live_view: [signing_salt: "xWABfDCj"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :sanctum, Sanctum.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  sanctum: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  sanctum: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :error, :game_id, :user_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# IANA timezone database for DateTime.shift_zone/2 — timestamps are stored in
# UTC and shifted to the browser's zone at render time (SanctumWeb.Timezone).
# `tz` compiles the IANA data in and never fetches at runtime.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
