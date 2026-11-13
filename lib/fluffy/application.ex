defmodule Fluffy.Application do
  @moduledoc false

  use Application

  # Browsers come from PlaywrightEx.Test's pool, which starts on first use and stops its
  # drivers after the suite.
  @impl true
  def start(_type, _args) do
    Fluffy.Sandbox.config()
    _config = Fluffy.Options.config!()

    Supervisor.start_link(
      [
        {Registry, keys: :unique, name: Fluffy.TestTimeout},
        {Task.Supervisor, name: Fluffy.TaskSupervisor},
        {DynamicSupervisor, strategy: :one_for_one, name: Fluffy.SessionRuntime.Supervisor}
      ],
      strategy: :rest_for_one,
      name: Fluffy.Supervisor
    )
  end
end
