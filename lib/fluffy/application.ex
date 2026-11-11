defmodule Fluffy.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Fluffy.Sandbox.config()
    validate_playwright_config()
    browser_children = children()

    # `mix test` and scripts halt the VM without stopping applications, so the
    # driver would outlive them. Exiting late, it restores the terminal settings it
    # saw at start over the shell's line editor (#213). At-exit hooks run before
    # the halt, after ExUnit's after-suite callbacks.
    if browser_children != [], do: System.at_exit(fn _status -> close_drivers() end)

    Supervisor.start_link(
      [{Task.Supervisor, name: Fluffy.TaskSupervisor}, {Registry, keys: :duplicate, name: Fluffy.Route.Registry}] ++
        browser_children ++ [{DynamicSupervisor, strategy: :one_for_one, name: Fluffy.SessionRuntime.Supervisor}],
      strategy: :rest_for_one,
      name: Fluffy.Supervisor
    )
  end

  # A driver whose pipe closes closes its browsers, and its close returns once it
  # has exited (ftes/playwright_ex#191).
  @doc false
  def close_drivers do
    Supervisor.terminate_child(Fluffy.Supervisor, Fluffy.BrowserRuntime.Supervisor)
  catch
    # The application has stopped already.
    :exit, {:noproc, _} -> {:error, :not_found}
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
