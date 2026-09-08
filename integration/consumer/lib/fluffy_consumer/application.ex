defmodule FluffyConsumer.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FluffyConsumerWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:fluffy_consumer, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FluffyConsumer.PubSub},
      # Start a worker by calling: FluffyConsumer.Worker.start_link(arg)
      # {FluffyConsumer.Worker, arg},
      # Start to serve requests, typically the last entry
      FluffyConsumerWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FluffyConsumer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FluffyConsumerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
