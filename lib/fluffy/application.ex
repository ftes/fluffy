defmodule Fluffy.Application do
  @moduledoc false

  use Application

  # Browsers come from PlaywrightEx.Test's pool, which starts on first use and stops its
  # drivers after the suite.
  @impl true
  def start(_type, _args) do
    Fluffy.Sandbox.config()
    Fluffy.Options.playwright_config()

    Supervisor.start_link(
      [
        {Task.Supervisor, name: Fluffy.TaskSupervisor},
        {Registry, keys: :duplicate, name: Fluffy.Route.Registry},
        {DynamicSupervisor, strategy: :one_for_one, name: Fluffy.SessionRuntime.Supervisor}
      ],
      strategy: :rest_for_one,
      name: Fluffy.Supervisor
    )
  end
end
