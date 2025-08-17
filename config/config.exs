# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
import Config

# Database disabled: using filesystem-backed persistence

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.0",
  default: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.6",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configure Oban
config :fsm_app, Oban,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron, crontab: [
      {"0 0 * * *", FSMApp.Jobs.DailyCleanup}
    ]}
  ],
  queues: [
    default: 10,
    events: 20,
    fsm_operations: 15
  ]

# Configure Guardian
config :fsm_app, FSMAppWeb.Auth.Guardian,
  issuer: "fsm_app",
  secret_key: "gZH75aKtMN3Yj0iPS4hcgUuTwjAzZr9C",
  ttl: {24, :hours}

# Configure Prometheus
config :fsm_app, PrometheusEx,
  metrics: [
    {PrometheusEx.Metrics.Counter, name: :http_requests_total, help: "Total number of HTTP requests"},
    {PrometheusEx.Metrics.Histogram, name: :http_request_duration_seconds, help: "HTTP request duration in seconds"}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
