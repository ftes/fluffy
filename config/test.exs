import Config

alias Ecto.Adapters.SQL.Sandbox
alias Fluffy.Support.Repo
alias Fluffy.Support.RepoTwo
alias Fluffy.Support.Web.Endpoint

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
  render_errors: [formats: [html: Fluffy.Support.Web.ErrorHTML], layout: false],
  secret_key_base: String.duplicate("fluffy-secret-", 8),
  server: true,
  url: [host: "127.0.0.1", port: 0, scheme: "http"]

config :fluffy, Fluffy.Sandbox,
  header: "user-agent",
  sandbox: Fluffy.Support.Sandbox

config :fluffy, Repo,
  pool: Sandbox,
  pool_size: System.schedulers_online() * 2,
  database: System.get_env("FLUFFY_DB_NAME", "postgres"),
  hostname: System.get_env("FLUFFY_DB_HOST", "127.0.0.1"),
  password: System.get_env("FLUFFY_DB_PASSWORD", "postgres"),
  port: String.to_integer(System.get_env("FLUFFY_DB_PORT", "5432")),
  username: System.get_env("FLUFFY_DB_USER", "postgres")

config :fluffy, RepoTwo,
  pool: Sandbox,
  pool_size: System.schedulers_online() * 2,
  database: System.get_env("FLUFFY_DB_NAME", "postgres"),
  hostname: System.get_env("FLUFFY_DB_HOST", "127.0.0.1"),
  password: System.get_env("FLUFFY_DB_PASSWORD", "postgres"),
  port: String.to_integer(System.get_env("FLUFFY_DB_PORT", "5432")),
  username: System.get_env("FLUFFY_DB_USER", "postgres")

config :fluffy,
  ecto_repos: [Repo, RepoTwo],
  endpoint: Endpoint,
  playwright: [timeout: 15_000]

# The tests write their baselines on first use: written and passed, not failed at the test's end.
config :playwright_ex, :expect, update_snapshots: :missing
config :playwright_ex, :test, browser_name: browser_engine, launch_options: [headless: true]

# CI keeps a screenshot of each failed test's pages in FLUFFY_ARTIFACT_DIR.
if artifact_dir = System.get_env("FLUFFY_ARTIFACT_DIR") do
  config :playwright_ex, :test, output_dir: artifact_dir, screenshot: :only_on_failure
end

config :logger, level: :warning
