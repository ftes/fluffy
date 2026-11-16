import Config

if config_env() in [:dev, :test] do
  config :esbuild,
    version: "0.28.2",
    test_browser: [
      args:
        ~w(assets/js/test_browser.js --bundle --format=esm --target=es2022 --outfile=priv/static/assets/test_browser.js),
      cd: Path.expand("..", __DIR__),
      env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
    ]
end

config :fluffy, ecto_repos: []

import_config "#{config_env()}.exs"
