defmodule Fluffy.TestServer do
  @moduledoc false

  use Supervisor

  alias Fluffy.TestWeb.Endpoint

  def start_link(_options \\ []) do
    configure_endpoint(lease_port())
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def base_url do
    Endpoint.url()
  end

  @impl true
  def init([]) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: Fluffy.TestServices},
      {Registry, keys: :duplicate, name: Fluffy.TestTimingProbe},
      Fluffy.TestDatabase,
      Fluffy.TestHTTPFixtures,
      {Phoenix.PubSub, name: Fluffy.TestPubSub},
      Endpoint
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp configure_endpoint(port) do
    config = Application.fetch_env!(:fluffy, Endpoint)

    config =
      config
      |> Keyword.put(:http, ip: {127, 0, 0, 1}, port: port)
      |> Keyword.put(:url, host: "127.0.0.1", port: port, scheme: "http")

    Application.put_env(:fluffy, Endpoint, config)
  end

  defp lease_port do
    {:ok, socket} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

    {:ok, {_address, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
