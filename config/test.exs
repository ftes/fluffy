import Config

alias Ecto.Adapters.SQL.Sandbox
alias Fluffy.TestWeb.Endpoint

browser_engine =
  case System.get_env("FLUFFY_BROWSER", "chromium") do
    "chromium" -> :chromium
    "firefox" -> :firefox
    "webkit" -> :webkit
    unsupported -> raise "unsupported FLUFFY_BROWSER: #{inspect(unsupported)}"
  end

config :fluffy, Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: 0],
  live_view: [signing_salt: "fluffy-live-view"],
  pubsub_server: Fluffy.TestPubSub,
  render_errors: [formats: [html: Fluffy.TestWeb.ErrorHTML], layout: false],
  secret_key_base: String.duplicate("fluffy-secret-", 8),
  server: true,
  url: [host: "127.0.0.1", port: 0, scheme: "http"]

config :fluffy, Fluffy.Sandbox,
  header: "user-agent",
  sandbox: Fluffy.TestSandbox

config :fluffy, Fluffy.TestRepo,
  pool: Sandbox,
  pool_size: System.schedulers_online() * 2,
  database: System.get_env("FLUFFY_DB_NAME", "postgres"),
  hostname: System.get_env("FLUFFY_DB_HOST", "127.0.0.1"),
  password: System.get_env("FLUFFY_DB_PASSWORD", "postgres"),
  port: String.to_integer(System.get_env("FLUFFY_DB_PORT", "5432")),
  username: System.get_env("FLUFFY_DB_USER", "postgres")

config :fluffy, Fluffy.TestRepoTwo,
  pool: Sandbox,
  pool_size: System.schedulers_online() * 2,
  database: System.get_env("FLUFFY_DB_NAME", "postgres"),
  hostname: System.get_env("FLUFFY_DB_HOST", "127.0.0.1"),
  password: System.get_env("FLUFFY_DB_PASSWORD", "postgres"),
  port: String.to_integer(System.get_env("FLUFFY_DB_PORT", "5432")),
  username: System.get_env("FLUFFY_DB_USER", "postgres")

config :fluffy,
  ecto_repos: [Fluffy.TestRepo, Fluffy.TestRepoTwo],
  endpoint: Endpoint,
  playwright: [
    enabled: true,
    engine: browser_engine,
    executable: Path.expand("../node_modules/playwright/cli.js", __DIR__),
    timeout: 15_000,
    launch_options: [headless: true],
    artifact_dir: System.get_env("FLUFFY_ARTIFACT_DIR")
  ]

config :logger, level: :warning
