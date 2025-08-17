import Config

# Database disabled in test: using filesystem-backed persistence

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :fsm_app, FSMAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Z02aUBf+C2NiAS5JmN/1dURriaF/XJU9/xB0/hEAkMzX/QO40B1LLuU/h60uIG6M",
  live_view: [signing_salt: "GFtgmDS6uTK7QCPB"],
  pubsub_server: FSMApp.PubSub,
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
