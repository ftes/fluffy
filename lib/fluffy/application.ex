defmodule Fluffy.Application do
  @moduledoc false

  use Application

  # Browsers come from PlaywrightEx.Test's pool, which starts on first use and stops its
  # drivers after the suite.
  @impl true
  def start(_type, _args) do
    Fluffy.Sandbox.config()
    Fluffy.Options.reject_removed_config!()

    Supervisor.start_link(
      [
        {Registry, keys: :unique, name: Fluffy.Backend.Playwright.DefaultBrowser},
        {Task.Supervisor, name: Fluffy.TaskSupervisor},
        {DynamicSupervisor, strategy: :one_for_one, name: Fluffy.SessionRuntime.Supervisor}
      ],
      strategy: :rest_for_one,
      name: Fluffy.Supervisor
    )
  end
end
