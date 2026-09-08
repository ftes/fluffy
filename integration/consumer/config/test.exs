import Config

config :fluffy,
  ecto_repos: [],
  endpoint: FluffyConsumerWeb.Endpoint,
  playwright: [
    enabled: true,
    engine: :chromium,
    executable: Path.expand("../../../node_modules/playwright/cli.js", __DIR__),
    timeout: 15_000,
    launch_options: [headless: true],
    artifact_dir: System.get_env("FLUFFY_ARTIFACT_DIR")
  ]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :fluffy_consumer, FluffyConsumerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 0],
  secret_key_base: "y+Y0z9GU+uym4/KI0Ym23hV5FsKOvfHsoPZFVtONo1YKaS4MaiX8Wy0D/NwOg6sM",
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
