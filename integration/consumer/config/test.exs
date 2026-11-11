import Config

config :fluffy,
  ecto_repos: [],
  endpoint: FluffyConsumerWeb.Endpoint,
  playwright: [
    enabled: true,
    engine: :chromium,
    timeout: 15_000,
    launch_options: [headless: true]
  ]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :fluffy_consumer, FluffyConsumerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 0],
  secret_key_base: "nUKuuqXGdDCMZhgOdO7N4WMTxbxPOlNqxUuuXgi7SFZBq5Jsdw5u0LjHKEh+jnfg",
  server: true,
  url: [host: "configured.invalid", port: 0, scheme: "http"]

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
