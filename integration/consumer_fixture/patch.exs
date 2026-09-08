alias Igniter.Project.Config
alias Igniter.Project.Deps

playwright_config =
  {:code,
   Sourceror.parse_string!("""
   [
     enabled: true,
     engine: :chromium,
     executable: Path.expand("../../../node_modules/playwright/cli.js", __DIR__),
     timeout: 15_000,
     launch_options: [headless: true],
     artifact_dir: System.get_env("FLUFFY_ARTIFACT_DIR")
   ]
   """)}

fixture_dir = __DIR__

Igniter.new()
|> Deps.add_dep({:fluffy, path: "../..", only: :test}, yes?: true)
|> Config.configure(
  "test.exs",
  :fluffy_consumer,
  [FluffyConsumerWeb.Endpoint, :http],
  ip: {127, 0, 0, 1},
  port: 0
)
|> Config.configure(
  "test.exs",
  :fluffy_consumer,
  [FluffyConsumerWeb.Endpoint, :url],
  host: "configured.invalid",
  port: 0,
  scheme: "http"
)
|> Config.configure(
  "test.exs",
  :fluffy_consumer,
  [FluffyConsumerWeb.Endpoint, :server],
  true
)
|> Config.configure_runtime_env(
  :test,
  :fluffy_consumer,
  [FluffyConsumerWeb.Endpoint, :http],
  ip: {127, 0, 0, 1},
  port: 0
)
|> Config.configure("test.exs", :fluffy, [:ecto_repos], [])
|> Config.configure(
  "test.exs",
  :fluffy,
  [:endpoint],
  FluffyConsumerWeb.Endpoint
)
|> Config.configure("test.exs", :fluffy, [:playwright], playwright_config)
|> Igniter.Libs.Phoenix.append_to_scope(
  "/",
  ~s(get "/complete", PageController, :complete),
  router: FluffyConsumerWeb.Router,
  arg2: FluffyConsumerWeb,
  with_pipelines: [:browser]
)
|> Igniter.create_new_file(
  "lib/fluffy_consumer_web/controllers/page_controller.ex",
  File.read!(Path.join(fixture_dir, "page_controller.ex")),
  on_exists: :overwrite
)
|> Igniter.create_new_file(
  "lib/fluffy_consumer_web/controllers/page_html/home.html.heex",
  File.read!(Path.join(fixture_dir, "home.html.heex")),
  on_exists: :overwrite
)
|> Igniter.rm("test/fluffy_consumer_web/controllers/page_controller_test.exs")
|> Igniter.create_new_file(
  "test/adoption_test.exs",
  File.read!(Path.join(fixture_dir, "adoption_test.exs"))
)
|> Deps.remove_dep(:igniter)
|> Igniter.do_or_dry_run(yes: true, title: "Apply the Fluffy consumer fixture")
