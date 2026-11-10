defmodule Fluffy.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Fluffy.Sandbox.config()
    validate_playwright_config()

    Supervisor.start_link(
      [{Task.Supervisor, name: Fluffy.TaskSupervisor}, {Registry, keys: :duplicate, name: Fluffy.Route.Registry}] ++
        children() ++ [{DynamicSupervisor, strategy: :one_for_one, name: Fluffy.SessionRuntime.Supervisor}],
      strategy: :rest_for_one,
      name: Fluffy.Supervisor
    )
  end

  defp children do
    case playwright_config() do
      false ->
        []

      config ->
        if Keyword.get(config, :enabled, true) do
          timeout = Keyword.fetch!(config, :timeout)

          [
            {DynamicSupervisor, strategy: :one_for_one, name: Fluffy.BrowserRuntime.Supervisor},
            {Fluffy.BrowserRuntime,
             timeout: timeout,
             engine: Keyword.get(config, :engine, :chromium),
             pool_size: Keyword.fetch!(config, :pool_size),
             playwright_options: Keyword.take(config, [:executable]),
             launch_options: Keyword.fetch!(config, :launch_options)}
          ]
        else
          []
        end
    end
  end

  defp validate_playwright_config do
    playwright_config()
    :ok
  end

  defp playwright_config do
    :fluffy
    |> Application.get_env(:playwright, false)
    |> Fluffy.Options.validate_playwright!()
  end
end
