import Config

config :fluffy,
  ecto_repos: [],
  playwright: false

import_config "#{config_env()}.exs"
