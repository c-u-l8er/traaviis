import Config

# Database disabled in dev: using filesystem-backed persistence

# Configure your endpoint
config :fsm_app, FSMAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "jfRbGgFaVo8bWBtV+T4NeM6ABMBvp/B+uARcO9/U4Q7YKni3Uc5lPFouABMaZQvT",
  live_view: [signing_salt: "GFtgmDS6uTK7QCPB"],
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]}
  ]

# Enable dev routes for dashboard and mailbox
config :fsm_app, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Configure Oban for development
config :fsm_app, Oban,
  testing: :inline,
  plugins: false
