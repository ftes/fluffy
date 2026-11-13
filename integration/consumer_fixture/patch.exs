alias Igniter.Project.Config
alias Igniter.Project.Deps

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
|> Config.configure("test.exs", :fluffy, [:action_timeout], 15_000)
|> Config.configure("test.exs", :playwright_ex, [:test, :launch_options], headless: true)
|> Config.configure("test.exs", :playwright_ex, [:test, :navigation_timeout], 15_000)
|> Igniter.Libs.Phoenix.append_to_scope(
  "/",
  """
  get "/hogwarts", PageController, :hogwarts
  get "/marauders-map", PageController, :marauders_map
  """,
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
