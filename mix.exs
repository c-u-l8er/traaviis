defmodule FSMApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :fsm_app,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases()
    ]
  end

  def application do
    [
      mod: {FSMApp.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core dependencies
      {:phoenix, "~> 1.7.10"},
      # Database-related deps removed (filesystem-backed persistence)
      {:phoenix_html, "~> 3.3"},
      {:phoenix_live_reload, "~> 1.4", only: :dev},
      {:phoenix_live_view, "~> 0.20.1"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.2"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2.0", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.3"},
      {:hackney, "~> 1.9"},
      {:finch, "~> 0.13"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.5"},

      # Authentication & Authorization
      {:bcrypt_elixir, "~> 3.0"},
      {:guardian, "~> 2.0"},

      # Database & Caching
      {:ecto_psql_extras, "~> 0.7"},
      {:redix, "~> 1.1"},

      # WebSocket & Real-time
      {:phoenix_pubsub, "~> 2.1"},

      # API & Serialization
      {:absinthe, "~> 1.7"},
      {:absinthe_phoenix, "~> 2.0"},
      {:absinthe_plug, "~> 1.5"},

      # Background Jobs
      {:oban, "~> 2.17"},

      # Monitoring & Observability
      {:prometheus_ex, "~> 3.0"},
      {:prometheus_plugs, "~> 1.1"},
      {:prometheus_phoenix, "~> 1.3"},
      # {:prometheus_ecto, "~> 1.4"}, # disabled: no Ecto repo

      # Development & Testing
      {:phoenix_integration, "~> 0.7", only: :test},
      {:ex_machina, "~> 2.7", only: :test},
      {:mox, "~> 1.1", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.3", only: [:dev, :test], runtime: false},

      # MCP Integration (Hermes)
      {:hermes_mcp, "~> 0.14.0"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      test: ["test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"]
    ]
  end

  defp releases do
    [
      fsm_app: [
        include_executables_for: [:unix],
        applications: [
          fsm_app: :permanent
        ]
      ]
    ]
  end
end
