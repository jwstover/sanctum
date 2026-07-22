defmodule Sanctum.MixProject do
  use Mix.Project

  def project do
    [
      app: :sanctum,
      version: "1.63.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      consolidate_protocols: Mix.env() not in [:dev, :prod_local],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ],
      dialyzer: [
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt"
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Sanctum.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:bcrypt_elixir, "~> 3.0"},
      {:tz, "~> 0.28"},
      {:hammer, "~> 7.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:usage_rules, "~> 1.2"},
      {:picosat_elixir, "~> 0.2"},
      {:sourceror, "~> 1.8"},
      {:oban, "~> 2.0"},
      {:ash_ai, "~> 0.2"},
      {:tidewave, "~> 0.2", only: [:dev, :prod_local]},
      {:live_debugger, "~> 1.0", only: [:dev, :prod_local]},
      {:ash_events, "~> 0.4"},
      {:ash_state_machine, "~> 0.2"},
      {:oban_web, "~> 2.0"},
      {:ash_oban, "~> 0.8"},
      {:ash_admin, "~> 1.0"},
      {:ash_authentication_phoenix, "~> 2.0"},
      {:ash_authentication, "~> 4.0"},
      {:ash_postgres, "~> 2.0"},
      {:ash_phoenix, "~> 2.0"},
      {:ash, "~> 3.0"},
      {:igniter, "~> 0.6"},
      {:phoenix, "~> 1.8.0-rc.4", override: true},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: [:dev, :prod_local]},
      {:phoenix_live_view, "~> 1.2"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() in [:dev, :prod_local]},
      {:tailwind, "~> 0.3", runtime: Mix.env() in [:dev, :prod_local]},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:resend, "~> 1.0.0-rc.3"},
      {:req, "~> 0.5"},
      {:vix, "~> 0.31"},
      {:sentry, "~> 13.3"},
      {:finch, "~> 0.21"},
      {:opentelemetry, "~> 1.7"},
      {:opentelemetry_api, "~> 1.5"},
      {:opentelemetry_exporter, "~> 1.10"},
      {:opentelemetry_semantic_conventions, "~> 1.27"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:opentelemetry_bandit, "~> 0.3"},
      {:opentelemetry_ecto, "~> 1.2"},
      {:opentelemetry_oban, "~> 1.2"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:nimble_parsec, "~> 1.4"},
      {:mdex, "~> 0.13"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:faker, "~> 0.18", only: :test}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    prod_local_guards() ++
      [
        ck: [
          "compile --warnings-as-errors",
          "format",
          "credo suggest --min-priority=normal",
          # Fails on ANY code duplication — extract the shared logic instead
          # of tolerating the clone. `mix ex_dna` shows the offending sites.
          # If a clone's fix rides another unmerged branch, a temporary
          # --max-clones N ratchet is acceptable; keep in sync with ci.yml.
          "ex_dna",
          "sobelow --config --exit"
        ],
        setup: [
          "deps.get",
          "ash.setup",
          "assets.setup",
          "assets.build",
          "run priv/repo/seeds.exs"
        ],
        "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
        "ecto.reset": ["ecto.drop", "ecto.setup"],
        test: ["ash.setup --quiet", "test"],
        "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
        "assets.build": ["tailwind sanctum", "esbuild sanctum"],
        "assets.deploy": [
          "tailwind sanctum --minify",
          "esbuild sanctum --minify",
          "phx.digest"
        ]
      ]
  end

  # MIX_ENV=prod_local points Sanctum.Repo at the PRODUCTION database
  # (see config/prod_local.exs). Any task that creates, drops, migrates, or
  # seeds the database must never run there, so these guards shadow them.
  # Aliases are looked up first-match, so prepending wins over the real ones.
  defp prod_local_guards do
    if Mix.env() == :prod_local do
      for task <- ~w(setup ecto.setup ecto.reset ecto.create ecto.drop ecto.migrate
                     ecto.rollback ash.setup ash.reset ash.migrate) do
        {String.to_atom(task),
         [
           fn _ ->
             Mix.raise(
               "Refusing to run `mix #{task}` under MIX_ENV=prod_local — " <>
                 "it targets the PRODUCTION database. Run it in :dev instead."
             )
           end
         ]}
      end
    else
      []
    end
  end
end
