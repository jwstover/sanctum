import Config

# prod_local: run the app locally with the full dev tooling (code reloader,
# Tidewave, LiveDashboard) but connected to the PRODUCTION database on Neon.
#
# Usage: scripts/prod_local (sources .env.prod_local, starts the server on
# port 4151). Destructive mix tasks (ecto.*, ash.setup, setup, …) are refused
# in this env by guards in mix.exs — see `prod_local_guards/0`.

import_config "dev.exs"

database_url =
  System.get_env("PROD_DATABASE_URL") ||
    raise """
    environment variable PROD_DATABASE_URL is missing.

    Copy .env.prod_local.example to .env.prod_local, fill in the prod
    connection string, and run commands through scripts/prod_local — or
    export PROD_DATABASE_URL yourself.
    """

# The :url option overrides the discrete host/user/password/database keys
# inherited from dev.exs. SSL setup mirrors config/runtime.exs (Neon requires
# TLS with hostname verification).
config :sanctum, Sanctum.Repo,
  url: database_url,
  ssl: [
    verify: :verify_peer,
    cacerts: :public_key.cacerts_get(),
    server_name_indication: String.to_charlist(URI.parse(database_url).host),
    customize_hostname_check: [
      match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
    ]
  ],
  pool_size: 3,
  # Never print the prod connection string into local logs.
  show_sensitive_data_on_connection_error: false

# A local node must never execute or schedule production background jobs:
# no queues, no Cron/Lifeline/Pruner plugins. (Sanctum.Oban.BootRescue is
# also skipped in this env — see that module.)
config :sanctum, Oban, queues: false, plugins: false

# Port 4151 so a normal dev server (4150) can run at the same time and the
# two are hard to confuse.
config :sanctum, SanctumWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4151")]
