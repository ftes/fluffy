# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :fluffy_consumer,
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :fluffy_consumer, FluffyConsumerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FluffyConsumerWeb.ErrorHTML, json: FluffyConsumerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FluffyConsumer.PubSub,
  live_view: [signing_salt: "oAYrJSP/"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
